export interface UsageMeter {
  unit: "app-tokens" | "provider-credits" | "estimated-usd" | "provider-quota";
  amount: number | null;
  source: string;
}

export interface Integration {
  id: string;
  provider: string;
  label: string;
  billingType: string | null;
  authState: string;
  availability: string;
  availabilityLabel: string;
  detectedApiKey: boolean;
  meteredAuthorized: boolean;
  configured: boolean;
  cliInstalled: boolean;
  usage: UsageMeter[];
}

export interface ModelInfo {
  id: string;
  provider: string;
  name: string;
  modelClass: string;
  enabled: boolean;
  cliAlias: string | null;
}

export interface WorkspaceSummary {
  id: string;
  name: string;
  agentLimit: number;
  projectCount: number;
  createdAt: string;
}

export interface TaskSummary {
  id: string;
  workspaceId: string;
  projectId: string;
  title: string;
  complexity: string;
  status: string;
  createdAt: string;
}

export interface AuditEntry {
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

export interface Approval {
  id: string;
  executionId: string;
  taskId: string;
  prompt: string;
  accountId: string;
  modelId: string;
  alternativesJson: string;
  status: string;
}

export interface ApprovalPolicy {
  category: string;
  mode: "automatic" | "require-approval" | "forbidden";
}

export interface Snapshot {
  organization: { id: string; name: string; mode: "economic" | "balanced" | "restricted" };
  workspaces: WorkspaceSummary[];
  integrations: Integration[];
  models: ModelInfo[];
  tasks: TaskSummary[];
  approvals: Approval[];
  approvalPolicies: ApprovalPolicy[];
  audit: AuditEntry[];
}

export interface PlanAgent {
  role: string;
  accountId: string;
  modelId: string;
}

export interface ExecutionView {
  id: string;
  status: string;
  sessionId: string | null;
  resumable: boolean;
  interruptionReason: string | null;
  resumeKind: string | null;
  plan: { phases: string[]; agents: PlanAgent[]; sameAccount: true } | null;
  events: Array<{ id: string; type: string; payload: { message?: string; alternatives?: unknown[] }; at: string }>;
  approval: Approval | null;
}

export interface TaskView {
  task: TaskSummary & { relevant: boolean; destructive: boolean };
  executions: ExecutionView[];
}

const headers = {
  "content-type": "application/json",
  "x-ai-workforce-actor": "local-operator",
};

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: { ...headers, ...init?.headers },
  });
  const payload = (await response.json()) as T & { error?: string };
  if (!response.ok) throw new Error(payload.error ?? "Falha na API local.");
  return payload;
}

export const api = {
  snapshot: () => request<Snapshot>("/api/snapshot"),
  setMode: (mode: Snapshot["organization"]["mode"]) =>
    request("/api/organization", { method: "PATCH", body: JSON.stringify({ mode }) }),
  createWorkspace: (name: string) => request<WorkspaceSummary>("/api/workspaces", { method: "POST", body: JSON.stringify({ name }) }),
  workspace: (id: string) => request<WorkspaceDetail>(`/api/workspaces/${id}`),
  savePolicy: (workspaceId: string, accountId: string, body: PolicyInput) =>
    request<WorkspaceDetail>(`/api/workspaces/${workspaceId}/policies/${accountId}`, { method: "PUT", body: JSON.stringify(body) }),
  setBudget: (workspaceId: string, limitAmount: number | null) =>
    request(`/api/workspaces/${workspaceId}/budget`, { method: "PUT", body: JSON.stringify({ limitAmount }) }),
  createProject: (workspaceId: string, name: string, path: string) =>
    request<{ id: string }>(`/api/workspaces/${workspaceId}/projects`, { method: "POST", body: JSON.stringify({ name, path }) }),
  project: (id: string) => request<{ project: { id: string; name: string; path: string; workspaceId: string }; tasks: TaskSummary[] }>(`/api/projects/${id}`),
  createTask: (projectId: string, body: Record<string, unknown>) =>
    request<TaskView>(`/api/projects/${projectId}/tasks`, { method: "POST", body: JSON.stringify(body) }),
  task: (id: string) => request<TaskView>(`/api/tasks/${id}`),
  pause: (id: string) => request<TaskView>(`/api/tasks/${id}/pause`, { method: "POST", body: "{}" }),
  resume: (id: string, confirmNew: boolean) =>
    request<{ task: TaskView; resume: { outcome: string; applied: boolean; label: string; message: string } }>(`/api/tasks/${id}/resume`, {
      method: "POST",
      body: JSON.stringify({ confirmNew }),
    }),
  decide: (id: string, body: Record<string, unknown>) => request<TaskView>(`/api/approvals/${id}`, { method: "POST", body: JSON.stringify(body) }),
  enableModel: (id: string, enabled: boolean) =>
    request(`/api/models/${id}/enabled`, { method: "POST", body: JSON.stringify({ enabled }) }),
  setApprovalPolicy: (category: string, mode: ApprovalPolicy["mode"]) =>
    request<ApprovalPolicy[]>(`/api/approval-policies/${category}`, { method: "PUT", body: JSON.stringify({ mode }) }),
};

export interface PolicyInput {
  decision: "allow" | "allow-with-approval" | "deny";
  billingType: string | null;
  label: string;
  authorizedModelIds: string[];
  meteredAuthorized: boolean;
}

export interface WorkspaceDetail {
  workspace: WorkspaceSummary;
  projects: Array<{ id: string; name: string; path: string }>;
  tasks: TaskSummary[];
  policies: Array<{
    accountId: string;
    provider: string;
    label: string;
    billingType: string | null;
    decision: PolicyInput["decision"] | null;
    authorizedModelIds: string[];
    meteredAuthorized: boolean;
    configured: boolean;
  }>;
  budget: { unit: string; limitAmount: number } | null;
}
