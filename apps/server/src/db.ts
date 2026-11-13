import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";

export function dataFile(): string {
  const root = process.env.AI_WORKFORCE_HOME ?? join(homedir(), ".ai-workforce");
  return join(root, "workforce.sqlite");
}

export function openDatabase(path: string): DatabaseSync {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec("PRAGMA foreign_keys = ON");
  if (path !== ":memory:") db.exec("PRAGMA journal_mode = WAL");
  return db;
}

export function migrate(db: DatabaseSync): void {
  db.exec(`
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
  `);
  seed(db);
}

function seed(db: DatabaseSync): void {
  const now = new Date().toISOString();
  const org = db.prepare("SELECT id FROM organizations WHERE id = ?").get("org-local");
  if (!org) {
    db.prepare("INSERT INTO organizations (id, name, mode, created_at) VALUES (?, ?, ?, ?)").run(
      "org-local",
      "Organização local",
      "economic",
      now,
    );
  }

  const accounts = [
    ["acc-claude", "claude-code", "Claude Code"],
    ["acc-codex", "codex", "Codex"],
    ["acc-cursor", "cursor", "Cursor"],
    ["acc-copilot", "copilot", "GitHub Copilot"],
  ] as const;
  const insertAccount = db.prepare(
    `INSERT OR IGNORE INTO integration_accounts
      (id, provider, label, billing_type, auth_state, availability, detected_api_key, metered_authorized, configured)
      VALUES (?, ?, ?, NULL, 'disconnected', 'not-probed', 0, 0, 0)`,
  );
  for (const [id, provider, label] of accounts) insertAccount.run(id, provider, label);

  const categories = [
    "consumption",
    "skill-install",
    "mcp",
    "admin-command",
    "config-file",
    "global-instructions",
    "delete-files",
    "migration",
    "git-destructive",
    "cross-project",
    "extra-resources",
  ];
  const insertCategory = db.prepare("INSERT OR IGNORE INTO approval_policies (category, mode) VALUES (?, ?)");
  for (const category of categories) {
    insertCategory.run(category, category === "consumption" ? "automatic" : "require-approval");
  }
}
