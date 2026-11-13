import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type {
  ApprovalCategory,
  ApprovalMode,
  Availability,
  BillingType,
  Complexity,
  ExecutionStatus,
  OperationMode,
  PolicyDecision,
  ProviderId,
  TaskStatus,
} from "@ai-workforce/contracts";

export interface OrganizationRow {
  id: string;
  name: string;
  mode: OperationMode;
}

export interface WorkspaceRow {
  id: string;
  organizationId: string;
  name: string;
  agentLimit: number;
  createdAt: string;
}

export interface ProjectRow {
  id: string;
  workspaceId: string;
  name: string;
  path: string;
  createdAt: string;
}

export interface AccountRow {
  id: string;
  provider: ProviderId;
  label: string;
  billingType: BillingType | null;
  authState: "authenticated" | "unauthenticated" | "disconnected";
  availability: Availability;
  detectedApiKey: boolean;
  meteredAuthorized: boolean;
  configured: boolean;
}

export interface PolicyRow {
  scope: "organization" | "workspace" | "project" | "agent" | "execution";
  scopeId: string;
  accountId: string;
  decision: PolicyDecision;
}

export interface ExecutionRow {
  id: string;
  taskId: string;
  accountId: string | null;
  modelId: string | null;
  status: ExecutionStatus;
  sessionId: string | null;
  resumable: boolean;
  interruptionReason: string | null;
  planJson: string | null;
  resumeKind: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TaskRow {
  id: string;
  workspaceId: string;
  projectId: string;
  title: string;
  complexity: Complexity;
  relevant: boolean;
  destructive: boolean;
  status: TaskStatus;
  createdAt: string;
}

export interface ApprovalRow {
  id: string;
  executionId: string;
  taskId: string;
  prompt: string;
  accountId: string;
  modelId: string;
  alternativesJson: string;
  status: "pending" | "approved" | "denied";
  decision: string | null;
  limitAmount: number | null;
  createdAt: string;
  decidedAt: string | null;
}

export interface AuditRow {
  id: string;
  at: string;
  actor: string;
  action: string;
  provider: string | null;
  modelId: string | null;
  accountId: string | null;
  limitApproved: string | null;
  result: string;
  detail: string;
}

function bool(value: number): boolean {
  return value === 1;
}

function rows<T>(value: unknown): T[] {
  return value as T[];
}

export class Repository {
  constructor(private readonly db: DatabaseSync) {}

  transaction<T>(fn: () => T): T {
    this.db.exec("BEGIN");
    try {
      const result = fn();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  organization(): OrganizationRow {
    const row = this.db.prepare("SELECT id, name, mode FROM organizations WHERE id = ?").get("org-local") as {
      id: string;
      name: string;
      mode: OperationMode;
    };
    return row;
  }

  setMode(mode: OperationMode): void {
    this.db.prepare("UPDATE organizations SET mode = ? WHERE id = ?").run(mode, "org-local");
  }

  listWorkspaces(): Array<WorkspaceRow & { projectCount: number }> {
    const listed = this.db
      .prepare(
        `SELECT w.id, w.organization_id as organizationId, w.name, w.agent_limit as agentLimit, w.created_at as createdAt,
                (SELECT COUNT(*) FROM projects p WHERE p.workspace_id = w.id) as projectCount
         FROM workspaces w ORDER BY w.created_at`,
      )
      .all();
    return rows<WorkspaceRow & { projectCount: number }>(listed);
  }

  workspace(id: string): WorkspaceRow | undefined {
    return this.db
      .prepare(
        "SELECT id, organization_id as organizationId, name, agent_limit as agentLimit, created_at as createdAt FROM workspaces WHERE id = ?",
      )
      .get(id) as WorkspaceRow | undefined;
  }

  insertWorkspace(name: string): WorkspaceRow {
    const row: WorkspaceRow = {
      id: randomUUID(),
      organizationId: "org-local",
      name,
      agentLimit: 4,
      createdAt: new Date().toISOString(),
    };
    this.db
      .prepare("INSERT INTO workspaces (id, organization_id, name, agent_limit, created_at) VALUES (?, ?, ?, ?, ?)")
      .run(row.id, row.organizationId, row.name, row.agentLimit, row.createdAt);
    return row;
  }

  listProjects(workspaceId: string): ProjectRow[] {
    const listed = this.db
      .prepare(
        "SELECT id, workspace_id as workspaceId, name, path, created_at as createdAt FROM projects WHERE workspace_id = ? ORDER BY created_at",
      )
      .all(workspaceId);
    return rows<ProjectRow>(listed);
  }

  project(id: string): ProjectRow | undefined {
    return this.db
      .prepare("SELECT id, workspace_id as workspaceId, name, path, created_at as createdAt FROM projects WHERE id = ?")
      .get(id) as ProjectRow | undefined;
  }

  insertProject(workspaceId: string, name: string, path: string): ProjectRow {
    const row: ProjectRow = { id: randomUUID(), workspaceId, name, path, createdAt: new Date().toISOString() };
    this.db
      .prepare("INSERT INTO projects (id, workspace_id, name, path, created_at) VALUES (?, ?, ?, ?, ?)")
      .run(row.id, row.workspaceId, row.name, row.path, row.createdAt);
    return row;
  }

  accounts(): AccountRow[] {
    const rows = this.db
      .prepare(
        `SELECT id, provider, label, billing_type as billingType, auth_state as authState, availability,
                detected_api_key as detectedApiKey, metered_authorized as meteredAuthorized, configured
         FROM integration_accounts ORDER BY id`,
      )
      .all() as Array<Omit<AccountRow, "detectedApiKey" | "meteredAuthorized" | "configured"> & {
      detectedApiKey: number;
      meteredAuthorized: number;
      configured: number;
    }>;
    return rows.map((row) => ({
      ...row,
      detectedApiKey: bool(row.detectedApiKey),
      meteredAuthorized: bool(row.meteredAuthorized),
      configured: bool(row.configured),
    }));
  }

  account(id: string): AccountRow | undefined {
    return this.accounts().find((item) => item.id === id);
  }

  updateAccount(input: {
    id: string;
    label: string;
    billingType: BillingType | null;
    meteredAuthorized: boolean;
  }): void {
    this.db
      .prepare(
        `UPDATE integration_accounts
         SET label = ?, billing_type = ?, metered_authorized = ?, configured = 1
         WHERE id = ?`,
      )
      .run(input.label, input.billingType, input.meteredAuthorized ? 1 : 0, input.id);
  }

  setAvailability(id: string, availability: Availability, authState: AccountRow["authState"]): void {
    this.db.prepare("UPDATE integration_accounts SET availability = ?, auth_state = ? WHERE id = ?").run(availability, authState, id);
  }

  policiesFor(scopeIds: string[]): PolicyRow[] {
    if (scopeIds.length === 0) return [];
    const marks = scopeIds.map(() => "?").join(", ");
    const listed = this.db
      .prepare(
        `SELECT scope, scope_id as scopeId, account_id as accountId, decision
         FROM policies WHERE scope_id IN (${marks})`,
      )
      .all(...scopeIds);
    return rows<PolicyRow>(listed);
  }

  upsertPolicy(scope: PolicyRow["scope"], scopeId: string, accountId: string, decision: PolicyDecision): void {
    this.db
      .prepare(
        `INSERT INTO policies (id, scope, scope_id, account_id, decision)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (scope, scope_id, account_id) DO UPDATE SET decision = excluded.decision`,
      )
      .run(randomUUID(), scope, scopeId, accountId, decision);
  }

  modelIds(scope: string, scopeId: string, accountId: string): string[] {
    const rows = this.db
      .prepare("SELECT model_id as modelId FROM model_grants WHERE scope = ? AND scope_id = ? AND account_id = ?")
      .all(scope, scopeId, accountId) as Array<{ modelId: string }>;
    return rows.map((row) => row.modelId);
  }

  replaceModelGrants(scope: string, scopeId: string, accountId: string, modelIds: string[]): void {
    this.db.prepare("DELETE FROM model_grants WHERE scope = ? AND scope_id = ? AND account_id = ?").run(scope, scopeId, accountId);
    const insert = this.db.prepare("INSERT INTO model_grants (account_id, scope, scope_id, model_id) VALUES (?, ?, ?, ?)");
    for (const modelId of modelIds) insert.run(accountId, scope, scopeId, modelId);
  }

  overrides(): Record<string, boolean> {
    const rows = this.db.prepare("SELECT model_id as modelId, enabled FROM model_overrides").all() as Array<{
      modelId: string;
      enabled: number;
    }>;
    return Object.fromEntries(rows.map((row) => [row.modelId, row.enabled === 1]));
  }

  setOverride(modelId: string, enabled: boolean): void {
    this.db
      .prepare(
        `INSERT INTO model_overrides (model_id, enabled) VALUES (?, ?)
         ON CONFLICT (model_id) DO UPDATE SET enabled = excluded.enabled`,
      )
      .run(modelId, enabled ? 1 : 0);
  }

  budget(scopeId: string): { unit: string; limitAmount: number } | null {
    const row = this.db
      .prepare("SELECT unit, limit_amount as limitAmount FROM budgets WHERE scope = 'workspace' AND scope_id = ?")
      .get(scopeId) as { unit: string; limitAmount: number } | undefined;
    return row ?? null;
  }

  setBudget(scopeId: string, limitAmount: number): void {
    this.db
      .prepare(
        `INSERT INTO budgets (id, scope, scope_id, unit, limit_amount) VALUES (?, 'workspace', ?, 'app-tokens', ?)
         ON CONFLICT (scope, scope_id, unit) DO UPDATE SET limit_amount = excluded.limit_amount`,
      )
      .run(randomUUID(), scopeId, limitAmount);
  }

  clearBudget(scopeId: string): void {
    this.db.prepare("DELETE FROM budgets WHERE scope = 'workspace' AND scope_id = ?").run(scopeId);
  }

  approvalMode(category: ApprovalCategory): ApprovalMode {
    const row = this.db.prepare("SELECT mode FROM approval_policies WHERE category = ?").get(category) as
      | { mode: ApprovalMode }
      | undefined;
    return row?.mode ?? "require-approval";
  }

  setApprovalMode(category: ApprovalCategory, mode: ApprovalMode): void {
    this.db.prepare("UPDATE approval_policies SET mode = ? WHERE category = ?").run(mode, category);
  }

  approvalPolicies(): Array<{ category: ApprovalCategory; mode: ApprovalMode }> {
    return this.db.prepare("SELECT category, mode FROM approval_policies ORDER BY category").all() as Array<{
      category: ApprovalCategory;
      mode: ApprovalMode;
    }>;
  }

  insertTask(input: Omit<TaskRow, "id" | "createdAt">): TaskRow {
    const row: TaskRow = { ...input, id: randomUUID(), createdAt: new Date().toISOString() };
    this.db
      .prepare(
        `INSERT INTO tasks (id, workspace_id, project_id, title, complexity, relevant, destructive, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        row.id,
        row.workspaceId,
        row.projectId,
        row.title,
        row.complexity,
        row.relevant ? 1 : 0,
        row.destructive ? 1 : 0,
        row.status,
        row.createdAt,
      );
    return row;
  }

  updateTaskStatus(id: string, status: TaskStatus): void {
    this.db.prepare("UPDATE tasks SET status = ? WHERE id = ?").run(status, id);
  }

  task(id: string): TaskRow | undefined {
    const row = this.db
      .prepare(
        `SELECT id, workspace_id as workspaceId, project_id as projectId, title, complexity,
                relevant, destructive, status, created_at as createdAt
         FROM tasks WHERE id = ?`,
      )
      .get(id) as (Omit<TaskRow, "relevant" | "destructive"> & { relevant: number; destructive: number }) | undefined;
    if (!row) return undefined;
    return { ...row, relevant: bool(row.relevant), destructive: bool(row.destructive) };
  }

  tasksByWorkspace(workspaceId: string): TaskRow[] {
    const rows = this.db
      .prepare(
        `SELECT id, workspace_id as workspaceId, project_id as projectId, title, complexity,
                relevant, destructive, status, created_at as createdAt
         FROM tasks WHERE workspace_id = ? ORDER BY created_at DESC`,
      )
      .all(workspaceId) as Array<Omit<TaskRow, "relevant" | "destructive"> & { relevant: number; destructive: number }>;
    return rows.map((row) => ({ ...row, relevant: bool(row.relevant), destructive: bool(row.destructive) }));
  }

  recentTasks(limit = 12): TaskRow[] {
    const rows = this.db
      .prepare(
        `SELECT id, workspace_id as workspaceId, project_id as projectId, title, complexity,
                relevant, destructive, status, created_at as createdAt
         FROM tasks ORDER BY created_at DESC LIMIT ?`,
      )
      .all(limit) as Array<Omit<TaskRow, "relevant" | "destructive"> & { relevant: number; destructive: number }>;
    return rows.map((row) => ({ ...row, relevant: bool(row.relevant), destructive: bool(row.destructive) }));
  }

  insertExecution(input: {
    taskId: string;
    accountId: string | null;
    modelId: string | null;
    status: ExecutionStatus;
    planJson: string | null;
    interruptionReason: string | null;
    resumeKind?: string | null;
  }): ExecutionRow {
    const now = new Date().toISOString();
    const row: ExecutionRow = {
      id: randomUUID(),
      taskId: input.taskId,
      accountId: input.accountId,
      modelId: input.modelId,
      status: input.status,
      sessionId: null,
      resumable: false,
      interruptionReason: input.interruptionReason,
      planJson: input.planJson,
      resumeKind: input.resumeKind ?? null,
      createdAt: now,
      updatedAt: now,
    };
    this.db
      .prepare(
        `INSERT INTO executions
          (id, task_id, account_id, model_id, status, session_id, resumable, interruption_reason, plan_json, resume_kind, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, NULL, 0, ?, ?, ?, ?, ?)`,
      )
      .run(
        row.id,
        row.taskId,
        row.accountId,
        row.modelId,
        row.status,
        row.interruptionReason,
        row.planJson,
        row.resumeKind,
        row.createdAt,
        row.updatedAt,
      );
    return row;
  }

  updateExecution(id: string, patch: Partial<Pick<ExecutionRow, "status" | "interruptionReason" | "planJson" | "modelId" | "accountId" | "resumeKind" | "sessionId" | "resumable">>): void {
    const current = this.execution(id);
    if (!current) return;
    const next = { ...current, ...patch, updatedAt: new Date().toISOString() };
    this.db
      .prepare(
        `UPDATE executions
         SET status = ?, interruption_reason = ?, plan_json = ?, model_id = ?, account_id = ?, resume_kind = ?,
             session_id = ?, resumable = ?, updated_at = ?
         WHERE id = ?`,
      )
      .run(
        next.status,
        next.interruptionReason,
        next.planJson,
        next.modelId,
        next.accountId,
        next.resumeKind,
        next.sessionId,
        next.resumable ? 1 : 0,
        next.updatedAt,
        id,
      );
  }

  execution(id: string): ExecutionRow | undefined {
    const row = this.db
      .prepare(
        `SELECT id, task_id as taskId, account_id as accountId, model_id as modelId, status, session_id as sessionId,
                resumable, interruption_reason as interruptionReason, plan_json as planJson, resume_kind as resumeKind,
                created_at as createdAt, updated_at as updatedAt
         FROM executions WHERE id = ?`,
      )
      .get(id) as (Omit<ExecutionRow, "resumable"> & { resumable: number }) | undefined;
    if (!row) return undefined;
    return { ...row, resumable: bool(row.resumable) };
  }

  executionsForTask(taskId: string): ExecutionRow[] {
    const rows = this.db
      .prepare(
        `SELECT id, task_id as taskId, account_id as accountId, model_id as modelId, status, session_id as sessionId,
                resumable, interruption_reason as interruptionReason, plan_json as planJson, resume_kind as resumeKind,
                created_at as createdAt, updated_at as updatedAt
         FROM executions WHERE task_id = ? ORDER BY created_at`,
      )
      .all(taskId) as Array<Omit<ExecutionRow, "resumable"> & { resumable: number }>;
    return rows.map((row) => ({ ...row, resumable: bool(row.resumable) }));
  }

  addEvent(executionId: string, type: string, payload: unknown): void {
    this.db
      .prepare("INSERT INTO execution_events (id, execution_id, type, payload_json, at) VALUES (?, ?, ?, ?, ?)")
      .run(randomUUID(), executionId, type, JSON.stringify(payload), new Date().toISOString());
  }

  events(executionId: string): Array<{ id: string; type: string; payload: unknown; at: string }> {
    const rows = this.db
      .prepare("SELECT id, type, payload_json as payloadJson, at FROM execution_events WHERE execution_id = ? ORDER BY at")
      .all(executionId) as Array<{ id: string; type: string; payloadJson: string; at: string }>;
    return rows.map((row) => ({ id: row.id, type: row.type, payload: JSON.parse(row.payloadJson) as unknown, at: row.at }));
  }

  insertGrant(input: {
    executionId: string;
    accountId: string;
    modelId: string;
    kind: "once" | "until-limit";
    limitAmount?: number;
  }): void {
    this.db
      .prepare(
        `INSERT INTO consumption_grants
          (id, execution_id, account_id, model_id, kind, limit_amount, consumed_amount, result, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, 'approved', ?)`,
      )
      .run(randomUUID(), input.executionId, input.accountId, input.modelId, input.kind, input.limitAmount ?? null, new Date().toISOString());
  }

  grantsFor(executionId: string) {
    return this.db
      .prepare(
        `SELECT execution_id as executionId, account_id as accountId, model_id as modelId, kind,
                limit_amount as limitAmount, consumed_amount as consumedAmount, result
         FROM consumption_grants WHERE execution_id = ? AND result = 'approved'`,
      )
      .all(executionId) as Array<{
      executionId: string;
      accountId: string;
      modelId: string;
      kind: "once" | "until-limit";
      limitAmount: number | null;
      consumedAmount: number | null;
      result: "approved";
    }>;
  }

  insertApproval(input: {
    executionId: string;
    taskId: string;
    prompt: string;
    accountId: string;
    modelId: string;
    alternatives: unknown;
  }): ApprovalRow {
    const row: ApprovalRow = {
      id: randomUUID(),
      executionId: input.executionId,
      taskId: input.taskId,
      prompt: input.prompt,
      accountId: input.accountId,
      modelId: input.modelId,
      alternativesJson: JSON.stringify(input.alternatives),
      status: "pending",
      decision: null,
      limitAmount: null,
      createdAt: new Date().toISOString(),
      decidedAt: null,
    };
    this.db
      .prepare(
        `INSERT INTO approvals
          (id, execution_id, task_id, prompt, account_id, model_id, alternatives_json, status, decision, limit_amount, created_at, decided_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, ?, NULL)`,
      )
      .run(row.id, row.executionId, row.taskId, row.prompt, row.accountId, row.modelId, row.alternativesJson, row.createdAt);
    return row;
  }

  approval(id: string): ApprovalRow | undefined {
    return this.mapApproval(
      this.db.prepare("SELECT * FROM approvals WHERE id = ?").get(id) as Record<string, unknown> | undefined,
    );
  }

  pendingApprovalForExecution(executionId: string): ApprovalRow | undefined {
    return this.mapApproval(
      this.db
        .prepare("SELECT * FROM approvals WHERE execution_id = ? AND status = 'pending' ORDER BY created_at DESC")
        .get(executionId) as Record<string, unknown> | undefined,
    );
  }

  pendingApprovals(): ApprovalRow[] {
    const rows = this.db.prepare("SELECT * FROM approvals WHERE status = 'pending' ORDER BY created_at DESC").all() as Array<
      Record<string, unknown>
    >;
    return rows.map((row) => this.mapApproval(row)).filter((row): row is ApprovalRow => Boolean(row));
  }

  decideApproval(id: string, decision: string, limitAmount: number | null, status: "approved" | "denied"): void {
    this.db
      .prepare("UPDATE approvals SET status = ?, decision = ?, limit_amount = ?, decided_at = ? WHERE id = ?")
      .run(status, decision, limitAmount, new Date().toISOString(), id);
  }

  audit(input: {
    actor: string;
    action: string;
    provider?: string | null;
    modelId?: string | null;
    accountId?: string | null;
    limitApproved?: string | null;
    result: string;
    detail: string;
  }): AuditRow {
    const row: AuditRow = {
      id: randomUUID(),
      at: new Date().toISOString(),
      actor: input.actor,
      action: input.action,
      provider: input.provider ?? null,
      modelId: input.modelId ?? null,
      accountId: input.accountId ?? null,
      limitApproved: input.limitApproved ?? null,
      result: input.result,
      detail: input.detail,
    };
    this.db
      .prepare(
        `INSERT INTO audit_log
          (id, at, actor, action, provider, model_id, account_id, limit_approved, result, detail)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(row.id, row.at, row.actor, row.action, row.provider, row.modelId, row.accountId, row.limitApproved, row.result, row.detail);
    return row;
  }

  recentAudit(limit = 30): AuditRow[] {
    const listed = this.db
      .prepare(
        `SELECT id, at, actor, action, provider, model_id as modelId, account_id as accountId,
                limit_approved as limitApproved, result, detail
         FROM audit_log ORDER BY at DESC LIMIT ?`,
      )
      .all(limit);
    return rows<AuditRow>(listed);
  }

  private mapApproval(row: Record<string, unknown> | undefined): ApprovalRow | undefined {
    if (!row) return undefined;
    return {
      id: String(row.id),
      executionId: String(row.execution_id),
      taskId: String(row.task_id),
      prompt: String(row.prompt),
      accountId: String(row.account_id),
      modelId: String(row.model_id),
      alternativesJson: String(row.alternatives_json),
      status: row.status as ApprovalRow["status"],
      decision: (row.decision as string | null) ?? null,
      limitAmount: (row.limit_amount as number | null) ?? null,
      createdAt: String(row.created_at),
      decidedAt: (row.decided_at as string | null) ?? null,
    };
  }
}
