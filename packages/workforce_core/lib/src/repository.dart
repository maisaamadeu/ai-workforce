import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'contracts.dart';
import 'database.dart';

class OrganizationRow {
  const OrganizationRow({
    required this.id,
    required this.name,
    required this.mode,
  });
  final String id;
  final String name;
  final OperationMode mode;
}

class WorkspaceRow {
  const WorkspaceRow({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.agentLimit,
    required this.createdAt,
    this.projectCount = 0,
  });

  final String id;
  final String organizationId;
  final String name;
  final int agentLimit;
  final String createdAt;
  final int projectCount;
}

class ProjectRow {
  const ProjectRow({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.path,
    required this.createdAt,
  });
  final String id;
  final String workspaceId;
  final String name;
  final String path;
  final String createdAt;
}

class AccountRow {
  const AccountRow({
    required this.id,
    required this.provider,
    required this.label,
    required this.billingType,
    required this.authState,
    required this.availability,
    required this.detectedApiKey,
    required this.meteredAuthorized,
    required this.configured,
  });

  final String id;
  final ProviderId provider;
  final String label;
  final BillingType? billingType;
  final AuthState authState;
  final Availability availability;
  final bool detectedApiKey;
  final bool meteredAuthorized;
  final bool configured;
}

class PolicyRow {
  const PolicyRow({
    required this.scope,
    required this.scopeId,
    required this.accountId,
    required this.decision,
  });
  final PolicyScope scope;
  final String scopeId;
  final String accountId;
  final PolicyDecision decision;
}

class ExecutionRow {
  const ExecutionRow({
    required this.id,
    required this.taskId,
    required this.accountId,
    required this.modelId,
    required this.status,
    required this.sessionId,
    required this.resumable,
    required this.interruptionReason,
    required this.planJson,
    required this.resumeKind,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String taskId;
  final String? accountId;
  final String? modelId;
  final ExecutionStatus status;
  final String? sessionId;
  final bool resumable;
  final String? interruptionReason;
  final String? planJson;
  final String? resumeKind;
  final String createdAt;
  final String updatedAt;

  ExecutionRow copyWith({
    ExecutionStatus? status,
    String? interruptionReason,
    String? planJson,
    String? modelId,
    String? accountId,
    String? resumeKind,
    String? sessionId,
    bool? resumable,
    bool clearInterruption = false,
  }) {
    return ExecutionRow(
      id: id,
      taskId: taskId,
      accountId: accountId ?? this.accountId,
      modelId: modelId ?? this.modelId,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      resumable: resumable ?? this.resumable,
      interruptionReason: clearInterruption
          ? interruptionReason
          : (interruptionReason ?? this.interruptionReason),
      planJson: planJson ?? this.planJson,
      resumeKind: resumeKind ?? this.resumeKind,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class TaskRow {
  const TaskRow({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.title,
    required this.complexity,
    required this.relevant,
    required this.destructive,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String projectId;
  final String title;
  final Complexity complexity;
  final bool relevant;
  final bool destructive;
  final TaskStatus status;
  final String createdAt;
}

class ApprovalRow {
  const ApprovalRow({
    required this.id,
    required this.executionId,
    required this.taskId,
    required this.prompt,
    required this.accountId,
    required this.modelId,
    required this.alternativesJson,
    required this.status,
    required this.decision,
    required this.limitAmount,
    required this.createdAt,
    required this.decidedAt,
  });

  final String id;
  final String executionId;
  final String taskId;
  final String prompt;
  final String accountId;
  final String modelId;
  final String alternativesJson;
  final String status;
  final String? decision;
  final double? limitAmount;
  final String createdAt;
  final String? decidedAt;
}

class AuditRow {
  const AuditRow({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    required this.provider,
    required this.modelId,
    required this.accountId,
    required this.limitApproved,
    required this.result,
    required this.detail,
  });

  final String id;
  final String at;
  final String actor;
  final String action;
  final String? provider;
  final String? modelId;
  final String? accountId;
  final String? limitApproved;
  final String result;
  final String detail;
}

class GrantRow {
  const GrantRow({
    required this.executionId,
    required this.accountId,
    required this.modelId,
    required this.kind,
    required this.limitAmount,
    required this.consumedAmount,
    required this.result,
  });

  final String executionId;
  final String accountId;
  final String modelId;
  final String kind;
  final double? limitAmount;
  final double? consumedAmount;
  final String result;
}

class Repository {
  Repository(this.db);
  final Database db;

  T transaction<T>(T Function() fn) {
    db.execute('BEGIN');
    try {
      final result = fn();
      db.execute('COMMIT');
      return result;
    } catch (error) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  OrganizationRow organization() {
    final row = db.select(
      'SELECT id, name, mode FROM organizations WHERE id = ?',
      ['org-local'],
    ).first;
    return OrganizationRow(
      id: row['id'] as String,
      name: row['name'] as String,
      mode: OperationMode.parse(row['mode'] as String),
    );
  }

  void setMode(OperationMode mode) {
    db.execute('UPDATE organizations SET mode = ? WHERE id = ?', [
      mode.name,
      'org-local',
    ]);
  }

  List<WorkspaceRow> listWorkspaces() {
    final listed = db.select('''
      SELECT w.id, w.organization_id as organizationId, w.name, w.agent_limit as agentLimit, w.created_at as createdAt,
             (SELECT COUNT(*) FROM projects p WHERE p.workspace_id = w.id) as projectCount
      FROM workspaces w ORDER BY w.created_at
    ''');
    return listed.map(_workspace).toList();
  }

  WorkspaceRow? workspace(String id) {
    final listed = db.select(
      'SELECT id, organization_id as organizationId, name, agent_limit as agentLimit, created_at as createdAt, 0 as projectCount FROM workspaces WHERE id = ?',
      [id],
    );
    if (listed.isEmpty) return null;
    return _workspace(listed.first);
  }

  WorkspaceRow insertWorkspace(String name) {
    final row = WorkspaceRow(
      id: freshId(),
      organizationId: 'org-local',
      name: name,
      agentLimit: 4,
      createdAt: _now(),
    );
    db.execute(
      'INSERT INTO workspaces (id, organization_id, name, agent_limit, created_at) VALUES (?, ?, ?, ?, ?)',
      [row.id, row.organizationId, row.name, row.agentLimit, row.createdAt],
    );
    return row;
  }

  List<ProjectRow> listProjects(String workspaceId) {
    return db
        .select(
          'SELECT id, workspace_id as workspaceId, name, path, created_at as createdAt FROM projects WHERE workspace_id = ? ORDER BY created_at',
          [workspaceId],
        )
        .map(_project)
        .toList();
  }

  ProjectRow? project(String id) {
    final listed = db.select(
      'SELECT id, workspace_id as workspaceId, name, path, created_at as createdAt FROM projects WHERE id = ?',
      [id],
    );
    if (listed.isEmpty) return null;
    return _project(listed.first);
  }

  ProjectRow insertProject(String workspaceId, String name, String path) {
    final row = ProjectRow(
      id: freshId(),
      workspaceId: workspaceId,
      name: name,
      path: path,
      createdAt: _now(),
    );
    db.execute(
      'INSERT INTO projects (id, workspace_id, name, path, created_at) VALUES (?, ?, ?, ?, ?)',
      [row.id, row.workspaceId, row.name, row.path, row.createdAt],
    );
    return row;
  }

  List<AccountRow> accounts() {
    return db
        .select('''
          SELECT id, provider, label, billing_type as billingType, auth_state as authState, availability,
                 detected_api_key as detectedApiKey, metered_authorized as meteredAuthorized, configured
          FROM integration_accounts ORDER BY id
        ''')
        .map(_account)
        .toList();
  }

  AccountRow? account(String id) {
    for (final item in accounts()) {
      if (item.id == id) return item;
    }
    return null;
  }

  void updateAccount({
    required String id,
    required String label,
    required BillingType? billingType,
    required bool meteredAuthorized,
  }) {
    db.execute(
      'UPDATE integration_accounts SET label = ?, billing_type = ?, metered_authorized = ?, configured = 1 WHERE id = ?',
      [label, billingType?.wire, meteredAuthorized ? 1 : 0, id],
    );
  }

  void setAvailability(
    String id,
    Availability availability,
    AuthState authState,
  ) {
    db.execute(
      'UPDATE integration_accounts SET availability = ?, auth_state = ? WHERE id = ?',
      [availability.wire, authState.name, id],
    );
  }

  List<PolicyRow> policiesFor(List<String> scopeIds) {
    if (scopeIds.isEmpty) return const [];
    final marks = List.filled(scopeIds.length, '?').join(', ');
    return db
        .select(
          'SELECT scope, scope_id as scopeId, account_id as accountId, decision FROM policies WHERE scope_id IN ($marks)',
          scopeIds,
        )
        .map((row) {
          return PolicyRow(
            scope: PolicyScope.values.byName(row['scope'] as String),
            scopeId: row['scopeId'] as String,
            accountId: row['accountId'] as String,
            decision: PolicyDecision.parse(row['decision'] as String),
          );
        })
        .toList();
  }

  void upsertPolicy(
    PolicyScope scope,
    String scopeId,
    String accountId,
    PolicyDecision decision,
  ) {
    db.execute(
      '''INSERT INTO policies (id, scope, scope_id, account_id, decision)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (scope, scope_id, account_id) DO UPDATE SET decision = excluded.decision''',
      [freshId(), scope.name, scopeId, accountId, decision.value],
    );
  }

  List<String> modelIds(String scope, String scopeId, String accountId) {
    return db
        .select(
          'SELECT model_id as modelId FROM model_grants WHERE scope = ? AND scope_id = ? AND account_id = ?',
          [scope, scopeId, accountId],
        )
        .map((row) => row['modelId'] as String)
        .toList();
  }

  void replaceModelGrants(
    String scope,
    String scopeId,
    String accountId,
    List<String> modelIds,
  ) {
    db.execute(
      'DELETE FROM model_grants WHERE scope = ? AND scope_id = ? AND account_id = ?',
      [scope, scopeId, accountId],
    );
    for (final modelId in modelIds) {
      db.execute(
        'INSERT INTO model_grants (account_id, scope, scope_id, model_id) VALUES (?, ?, ?, ?)',
        [accountId, scope, scopeId, modelId],
      );
    }
  }

  Map<String, bool> overrides() {
    return {
      for (final row in db.select(
        'SELECT model_id as modelId, enabled FROM model_overrides',
      ))
        row['modelId'] as String: row['enabled'] == 1,
    };
  }

  void setOverride(String modelId, bool enabled) {
    db.execute(
      '''INSERT INTO model_overrides (model_id, enabled) VALUES (?, ?)
         ON CONFLICT (model_id) DO UPDATE SET enabled = excluded.enabled''',
      [modelId, enabled ? 1 : 0],
    );
  }

  ({String unit, double limitAmount})? budget(String scopeId) {
    final listed = db.select(
      'SELECT unit, limit_amount as limitAmount FROM budgets WHERE scope = ? AND scope_id = ?',
      ['workspace', scopeId],
    );
    if (listed.isEmpty) return null;
    return (
      unit: listed.first['unit'] as String,
      limitAmount: (listed.first['limitAmount'] as num).toDouble(),
    );
  }

  void setBudget(String scopeId, double limitAmount) {
    db.execute(
      '''INSERT INTO budgets (id, scope, scope_id, unit, limit_amount) VALUES (?, 'workspace', ?, 'app-tokens', ?)
         ON CONFLICT (scope, scope_id, unit) DO UPDATE SET limit_amount = excluded.limit_amount''',
      [freshId(), scopeId, limitAmount],
    );
  }

  void clearBudget(String scopeId) {
    db.execute('DELETE FROM budgets WHERE scope = ? AND scope_id = ?', [
      'workspace',
      scopeId,
    ]);
  }

  ApprovalMode approvalMode(ApprovalCategory category) {
    final listed = db.select(
      'SELECT mode FROM approval_policies WHERE category = ?',
      [category.value],
    );
    if (listed.isEmpty) return ApprovalMode.requireApproval;
    return ApprovalMode.parse(listed.first['mode'] as String);
  }

  void setApprovalMode(ApprovalCategory category, ApprovalMode mode) {
    db.execute('UPDATE approval_policies SET mode = ? WHERE category = ?', [
      mode.value,
      category.value,
    ]);
  }

  List<({ApprovalCategory category, ApprovalMode mode})> approvalPolicies() {
    return db
        .select(
          'SELECT category, mode FROM approval_policies ORDER BY category',
        )
        .map((row) {
          return (
            category: ApprovalCategory.parse(row['category'] as String),
            mode: ApprovalMode.parse(row['mode'] as String),
          );
        })
        .toList();
  }

  TaskRow insertTask(TaskRow input) {
    final row = TaskRow(
      id: freshId(),
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      title: input.title,
      complexity: input.complexity,
      relevant: input.relevant,
      destructive: input.destructive,
      status: input.status,
      createdAt: _now(),
    );
    db.execute(
      '''INSERT INTO tasks (id, workspace_id, project_id, title, complexity, relevant, destructive, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        row.id,
        row.workspaceId,
        row.projectId,
        row.title,
        row.complexity.name,
        row.relevant ? 1 : 0,
        row.destructive ? 1 : 0,
        row.status.value,
        row.createdAt,
      ],
    );
    return row;
  }

  void updateTaskStatus(String id, TaskStatus status) {
    db.execute('UPDATE tasks SET status = ? WHERE id = ?', [status.value, id]);
  }

  TaskRow? task(String id) {
    final listed = db.select(
      '''SELECT id, workspace_id as workspaceId, project_id as projectId, title, complexity,
                relevant, destructive, status, created_at as createdAt
         FROM tasks WHERE id = ?''',
      [id],
    );
    if (listed.isEmpty) return null;
    return _task(listed.first);
  }

  List<TaskRow> tasksByWorkspace(String workspaceId) {
    return db
        .select(
          '''SELECT id, workspace_id as workspaceId, project_id as projectId, title, complexity,
                    relevant, destructive, status, created_at as createdAt
             FROM tasks WHERE workspace_id = ? ORDER BY created_at DESC''',
          [workspaceId],
        )
        .map(_task)
        .toList();
  }

  List<TaskRow> recentTasks([int limit = 12]) {
    return db
        .select(
          '''SELECT id, workspace_id as workspaceId, project_id as projectId, title, complexity,
                    relevant, destructive, status, created_at as createdAt
             FROM tasks ORDER BY created_at DESC LIMIT ?''',
          [limit],
        )
        .map(_task)
        .toList();
  }

  ExecutionRow insertExecution({
    required String taskId,
    required String? accountId,
    required String? modelId,
    required ExecutionStatus status,
    required String? planJson,
    required String? interruptionReason,
    String? resumeKind,
  }) {
    final now = _now();
    final row = ExecutionRow(
      id: freshId(),
      taskId: taskId,
      accountId: accountId,
      modelId: modelId,
      status: status,
      sessionId: null,
      resumable: false,
      interruptionReason: interruptionReason,
      planJson: planJson,
      resumeKind: resumeKind,
      createdAt: now,
      updatedAt: now,
    );
    db.execute(
      '''INSERT INTO executions
        (id, task_id, account_id, model_id, status, session_id, resumable, interruption_reason, plan_json, resume_kind, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, NULL, 0, ?, ?, ?, ?, ?)''',
      [
        row.id,
        row.taskId,
        row.accountId,
        row.modelId,
        row.status.value,
        row.interruptionReason,
        row.planJson,
        row.resumeKind,
        row.createdAt,
        row.updatedAt,
      ],
    );
    return row;
  }

  void updateExecution(String id, ExecutionRow patch) {
    db.execute(
      '''UPDATE executions
         SET status = ?, interruption_reason = ?, plan_json = ?, model_id = ?, account_id = ?, resume_kind = ?,
             session_id = ?, resumable = ?, updated_at = ?
         WHERE id = ?''',
      [
        patch.status.value,
        patch.interruptionReason,
        patch.planJson,
        patch.modelId,
        patch.accountId,
        patch.resumeKind,
        patch.sessionId,
        patch.resumable ? 1 : 0,
        _now(),
        id,
      ],
    );
  }

  ExecutionRow? execution(String id) {
    final listed = _executionQuery('WHERE id = ?', [id]);
    if (listed.isEmpty) return null;
    return listed.first;
  }

  List<ExecutionRow> executionsForTask(String taskId) =>
      _executionQuery('WHERE task_id = ? ORDER BY created_at', [taskId]);

  void addEvent(String executionId, String type, Map<String, Object?> payload) {
    db.execute(
      'INSERT INTO execution_events (id, execution_id, type, payload_json, at) VALUES (?, ?, ?, ?, ?)',
      [freshId(), executionId, type, jsonEncode(payload), _now()],
    );
  }

  List<({String id, String type, Map<String, Object?> payload, String at})>
  events(String executionId) {
    return db
        .select(
          'SELECT id, type, payload_json as payloadJson, at FROM execution_events WHERE execution_id = ? ORDER BY at',
          [executionId],
        )
        .map((row) {
          final decoded = jsonDecode(row['payloadJson'] as String);
          return (
            id: row['id'] as String,
            type: row['type'] as String,
            payload: (decoded as Map).cast<String, Object?>(),
            at: row['at'] as String,
          );
        })
        .toList();
  }

  void insertGrant({
    required String executionId,
    required String accountId,
    required String modelId,
    required String kind,
    double? limitAmount,
  }) {
    db.execute(
      '''INSERT INTO consumption_grants
        (id, execution_id, account_id, model_id, kind, limit_amount, consumed_amount, result, created_at)
        VALUES (?, ?, ?, ?, ?, ?, 0, 'approved', ?)''',
      [freshId(), executionId, accountId, modelId, kind, limitAmount, _now()],
    );
  }

  List<GrantRow> grantsFor(String executionId) {
    return db
        .select(
          '''SELECT execution_id as executionId, account_id as accountId, model_id as modelId, kind,
                limit_amount as limitAmount, consumed_amount as consumedAmount, result
         FROM consumption_grants WHERE execution_id = ? AND result = 'approved' ''',
          [executionId],
        )
        .map((row) {
          return GrantRow(
            executionId: row['executionId'] as String,
            accountId: row['accountId'] as String,
            modelId: row['modelId'] as String,
            kind: row['kind'] as String,
            limitAmount: (row['limitAmount'] as num?)?.toDouble(),
            consumedAmount: (row['consumedAmount'] as num?)?.toDouble(),
            result: row['result'] as String,
          );
        })
        .toList();
  }

  ApprovalRow insertApproval({
    required String executionId,
    required String taskId,
    required String prompt,
    required String accountId,
    required String modelId,
    required List<ModelOption> alternatives,
  }) {
    final row = ApprovalRow(
      id: freshId(),
      executionId: executionId,
      taskId: taskId,
      prompt: prompt,
      accountId: accountId,
      modelId: modelId,
      alternativesJson: jsonEncode(
        alternatives.map((item) => item.toJson()).toList(),
      ),
      status: 'pending',
      decision: null,
      limitAmount: null,
      createdAt: _now(),
      decidedAt: null,
    );
    db.execute(
      '''INSERT INTO approvals
        (id, execution_id, task_id, prompt, account_id, model_id, alternatives_json, status, decision, limit_amount, created_at, decided_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, ?, NULL)''',
      [
        row.id,
        row.executionId,
        row.taskId,
        row.prompt,
        row.accountId,
        row.modelId,
        row.alternativesJson,
        row.createdAt,
      ],
    );
    return row;
  }

  ApprovalRow? approval(String id) {
    final listed = db.select('SELECT * FROM approvals WHERE id = ?', [id]);
    if (listed.isEmpty) return null;
    return _approval(listed.first);
  }

  ApprovalRow? pendingApprovalForExecution(String executionId) {
    final listed = db.select(
      "SELECT * FROM approvals WHERE execution_id = ? AND status = 'pending' ORDER BY created_at DESC",
      [executionId],
    );
    if (listed.isEmpty) return null;
    return _approval(listed.first);
  }

  List<ApprovalRow> pendingApprovals() {
    return db
        .select(
          "SELECT * FROM approvals WHERE status = 'pending' ORDER BY created_at DESC",
        )
        .map(_approval)
        .toList();
  }

  void decideApproval(
    String id,
    String decision,
    double? limitAmount,
    String status,
  ) {
    db.execute(
      'UPDATE approvals SET status = ?, decision = ?, limit_amount = ?, decided_at = ? WHERE id = ?',
      [status, decision, limitAmount, _now(), id],
    );
  }

  void audit({
    required String actor,
    required String action,
    String? provider,
    String? modelId,
    String? accountId,
    String? limitApproved,
    required String result,
    required String detail,
  }) {
    db.execute(
      '''INSERT INTO audit_log
        (id, at, actor, action, provider, model_id, account_id, limit_approved, result, detail)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        freshId(),
        _now(),
        actor,
        action,
        provider,
        modelId,
        accountId,
        limitApproved,
        result,
        detail,
      ],
    );
  }

  List<AuditRow> recentAudit([int limit = 30]) {
    return db
        .select(
          '''SELECT id, at, actor, action, provider, model_id as modelId, account_id as accountId,
                limit_approved as limitApproved, result, detail
         FROM audit_log ORDER BY at DESC LIMIT ?''',
          [limit],
        )
        .map((row) {
          return AuditRow(
            id: row['id'] as String,
            at: row['at'] as String,
            actor: row['actor'] as String,
            action: row['action'] as String,
            provider: row['provider'] as String?,
            modelId: row['modelId'] as String?,
            accountId: row['accountId'] as String?,
            limitApproved: row['limitApproved'] as String?,
            result: row['result'] as String,
            detail: row['detail'] as String,
          );
        })
        .toList();
  }

  List<ExecutionRow> _executionQuery(String where, List<Object?> args) {
    return db
        .select(
          '''SELECT id, task_id as taskId, account_id as accountId, model_id as modelId, status, session_id as sessionId,
                resumable, interruption_reason as interruptionReason, plan_json as planJson, resume_kind as resumeKind,
                created_at as createdAt, updated_at as updatedAt
         FROM executions $where''',
          args,
        )
        .map((row) {
          return ExecutionRow(
            id: row['id'] as String,
            taskId: row['taskId'] as String,
            accountId: row['accountId'] as String?,
            modelId: row['modelId'] as String?,
            status: ExecutionStatus.parse(row['status'] as String),
            sessionId: row['sessionId'] as String?,
            resumable: row['resumable'] == 1,
            interruptionReason: row['interruptionReason'] as String?,
            planJson: row['planJson'] as String?,
            resumeKind: row['resumeKind'] as String?,
            createdAt: row['createdAt'] as String,
            updatedAt: row['updatedAt'] as String,
          );
        })
        .toList();
  }

  ApprovalRow _approval(Row row) {
    return ApprovalRow(
      id: row['id'] as String,
      executionId: row['execution_id'] as String,
      taskId: row['task_id'] as String,
      prompt: row['prompt'] as String,
      accountId: row['account_id'] as String,
      modelId: row['model_id'] as String,
      alternativesJson: row['alternatives_json'] as String,
      status: row['status'] as String,
      decision: row['decision'] as String?,
      limitAmount: (row['limit_amount'] as num?)?.toDouble(),
      createdAt: row['created_at'] as String,
      decidedAt: row['decided_at'] as String?,
    );
  }
}

WorkspaceRow _workspace(Row row) => WorkspaceRow(
  id: row['id'] as String,
  organizationId: row['organizationId'] as String,
  name: row['name'] as String,
  agentLimit: row['agentLimit'] as int,
  createdAt: row['createdAt'] as String,
  projectCount: row['projectCount'] as int,
);

ProjectRow _project(Row row) => ProjectRow(
  id: row['id'] as String,
  workspaceId: row['workspaceId'] as String,
  name: row['name'] as String,
  path: row['path'] as String,
  createdAt: row['createdAt'] as String,
);

AccountRow _account(Row row) => AccountRow(
  id: row['id'] as String,
  provider: ProviderId.parse(row['provider'] as String),
  label: row['label'] as String,
  billingType: row['billingType'] == null
      ? null
      : BillingType.parse(row['billingType'] as String),
  authState: AuthState.parse(row['authState'] as String),
  availability: Availability.parse(row['availability'] as String),
  detectedApiKey: row['detectedApiKey'] == 1,
  meteredAuthorized: row['meteredAuthorized'] == 1,
  configured: row['configured'] == 1,
);

TaskRow _task(Row row) => TaskRow(
  id: row['id'] as String,
  workspaceId: row['workspaceId'] as String,
  projectId: row['projectId'] as String,
  title: row['title'] as String,
  complexity: Complexity.values.byName(row['complexity'] as String),
  relevant: row['relevant'] == 1,
  destructive: row['destructive'] == 1,
  status: TaskStatus.parse(row['status'] as String),
  createdAt: row['createdAt'] as String,
);

String _now() => DateTime.now().toUtc().toIso8601String();
