import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'ids.dart';

var _sqliteReady = false;

void configureSqlite() {
  if (_sqliteReady) return;
  _sqliteReady = true;
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    for (final name in ['libsqlite3.so.0', 'libsqlite3.so']) {
      try {
        return DynamicLibrary.open(name);
      } on ArgumentError {
        continue;
      }
    }
    throw ArgumentError(
      'A biblioteca libsqlite3 não está instalada neste host.',
    );
  });
}

const schemaVersion = 1;

void migrate(Database db) {
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL
    )
  ''');
  final current = db.select(
    'SELECT version FROM schema_migrations WHERE version = ?',
    [schemaVersion],
  );
  if (current.isNotEmpty) return;
  db.execute('''
    CREATE TABLE IF NOT EXISTS organizations (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      mode TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS workspaces (
      id TEXT PRIMARY KEY,
      organization_id TEXT NOT NULL,
      name TEXT NOT NULL,
      agent_limit INTEGER NOT NULL DEFAULT 4,
      created_at TEXT NOT NULL,
      FOREIGN KEY (organization_id) REFERENCES organizations(id)
    );

    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      workspace_id TEXT NOT NULL,
      name TEXT NOT NULL,
      path TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (workspace_id) REFERENCES workspaces(id)
    );

    CREATE TABLE IF NOT EXISTS integration_accounts (
      id TEXT PRIMARY KEY,
      provider TEXT NOT NULL,
      label TEXT NOT NULL,
      billing_type TEXT,
      auth_state TEXT NOT NULL,
      availability TEXT NOT NULL,
      detected_api_key INTEGER NOT NULL DEFAULT 0,
      metered_authorized INTEGER NOT NULL DEFAULT 0,
      configured INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS policies (
      id TEXT PRIMARY KEY,
      scope TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      account_id TEXT NOT NULL,
      decision TEXT NOT NULL,
      UNIQUE (scope, scope_id, account_id)
    );

    CREATE TABLE IF NOT EXISTS model_grants (
      account_id TEXT NOT NULL,
      scope TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      model_id TEXT NOT NULL,
      PRIMARY KEY (account_id, scope, scope_id, model_id)
    );

    CREATE TABLE IF NOT EXISTS model_overrides (
      model_id TEXT PRIMARY KEY,
      enabled INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS budgets (
      id TEXT PRIMARY KEY,
      scope TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      unit TEXT NOT NULL,
      limit_amount REAL NOT NULL,
      UNIQUE (scope, scope_id, unit)
    );

    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      workspace_id TEXT NOT NULL,
      project_id TEXT NOT NULL,
      title TEXT NOT NULL,
      complexity TEXT NOT NULL,
      relevant INTEGER NOT NULL,
      destructive INTEGER NOT NULL,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS executions (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      account_id TEXT,
      model_id TEXT,
      status TEXT NOT NULL,
      session_id TEXT,
      resumable INTEGER NOT NULL DEFAULT 0,
      interruption_reason TEXT,
      plan_json TEXT,
      resume_kind TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS execution_events (
      id TEXT PRIMARY KEY,
      execution_id TEXT NOT NULL,
      type TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS consumption_grants (
      id TEXT PRIMARY KEY,
      execution_id TEXT NOT NULL,
      account_id TEXT NOT NULL,
      model_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      limit_amount REAL,
      consumed_amount REAL,
      result TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS approvals (
      id TEXT PRIMARY KEY,
      execution_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      prompt TEXT NOT NULL,
      account_id TEXT NOT NULL,
      model_id TEXT NOT NULL,
      alternatives_json TEXT NOT NULL,
      status TEXT NOT NULL,
      decision TEXT,
      limit_amount REAL,
      created_at TEXT NOT NULL,
      decided_at TEXT
    );

    CREATE TABLE IF NOT EXISTS approval_policies (
      category TEXT PRIMARY KEY,
      mode TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS audit_log (
      id TEXT PRIMARY KEY,
      at TEXT NOT NULL,
      actor TEXT NOT NULL,
      action TEXT NOT NULL,
      provider TEXT,
      model_id TEXT,
      account_id TEXT,
      limit_approved TEXT,
      result TEXT NOT NULL,
      detail TEXT NOT NULL
    );
  ''');
  _seed(db);
  db.execute(
    'INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)',
    [schemaVersion, _now()],
  );
}

Database openDatabase(String path) {
  configureSqlite();
  if (path != ':memory:') {
    final file = File(path);
    file.parent.createSync(recursive: true);
  }
  final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
  db.execute('PRAGMA foreign_keys = ON');
  if (path != ':memory:') db.execute('PRAGMA journal_mode = WAL');
  migrate(db);
  return db;
}

void _seed(Database db) {
  final now = _now();
  final org = db.select('SELECT id FROM organizations WHERE id = ?', [
    'org-local',
  ]);
  if (org.isEmpty) {
    db.execute(
      'INSERT INTO organizations (id, name, mode, created_at) VALUES (?, ?, ?, ?)',
      ['org-local', 'Organização local', 'economic', now],
    );
  }
  const accounts = [
    ['acc-claude', 'claude-code', 'Claude Code'],
    ['acc-codex', 'codex', 'Codex'],
    ['acc-cursor', 'cursor', 'Cursor'],
    ['acc-copilot', 'copilot', 'GitHub Copilot'],
  ];
  for (final account in accounts) {
    db.execute(
      '''INSERT OR IGNORE INTO integration_accounts
        (id, provider, label, billing_type, auth_state, availability, detected_api_key, metered_authorized, configured)
        VALUES (?, ?, ?, NULL, 'disconnected', 'not-probed', 0, 0, 0)''',
      account,
    );
  }
  const categories = [
    'consumption',
    'skill-install',
    'mcp',
    'admin-command',
    'config-file',
    'global-instructions',
    'delete-files',
    'migration',
    'git-destructive',
    'cross-project',
    'extra-resources',
  ];
  for (final category in categories) {
    db.execute(
      'INSERT OR IGNORE INTO approval_policies (category, mode) VALUES (?, ?)',
      [category, category == 'consumption' ? 'automatic' : 'require-approval'],
    );
  }
}

String _now() => DateTime.now().toUtc().toIso8601String();

String freshId() => newId();
