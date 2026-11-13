export type OperationMode = "economic" | "balanced" | "restricted";

export type ProviderId = "claude-code" | "codex" | "cursor" | "copilot";

export type BillingType =
  | "personal-subscription"
  | "corporate-subscription"
  | "metered-api"
  | "provider-credits"
  | "unmetered";

export type Availability =
  | "not-probed"
  | "disconnected"
  | "unauthenticated"
  | "available"
  | "unknown"
  | "quota-exhausted"
  | "restricted";

export type AuthState = "authenticated" | "unauthenticated" | "disconnected";

export type ModelClass = "economy" | "standard" | "reasoning" | "explicit-premium";

export type PolicyDecision = "allow" | "allow-with-approval" | "deny";

export type PolicyScope = "organization" | "workspace" | "project" | "agent" | "execution";

export type Complexity = "simple" | "standard" | "architecture";

export type Phase = "analyze" | "plan" | "implement" | "review";

export type AgentRole = "executor" | "architect" | "developer" | "reviewer";

export type ExecutionStatus =
  | "awaiting-authorization"
  | "awaiting-availability"
  | "paused-by-user"
  | "paused-by-limit"
  | "cancelling"
  | "cancelled"
  | "blocked"
  | "ready"
  | "failed";

export type UsageUnit = "app-tokens" | "provider-credits" | "estimated-usd" | "provider-quota";

export type ApprovalCategory =
  | "consumption"
  | "skill-install"
  | "mcp"
  | "admin-command"
  | "config-file"
  | "global-instructions"
  | "delete-files"
  | "migration"
  | "git-destructive"
  | "cross-project"
  | "extra-resources";

export type ApprovalMode = "automatic" | "require-approval" | "forbidden";

export type TaskStatus = "open" | "blocked" | "paused" | "awaiting-authorization" | "awaiting-availability" | "cancelled";

export const LOCAL_OPERATOR = "local-operator";

export const AGENT_ACTOR = "agent";

export const events = {
  authorizationRequested: "usage.authorization.requested",
  authorizationDecided: "usage.authorization.decided",
  availabilityChanged: "usage.availability.changed",
  quotaExhausted: "usage.quota.exhausted",
  executionStateChanged: "execution.state.changed",
  resumeRequested: "execution.resume.requested",
  resumeRejected: "execution.resume.rejected",
} as const;

export type WorkforceEventName = (typeof events)[keyof typeof events];

export const blockedMeteredEnv = [
  "ANTHROPIC_API_KEY",
  "OPENAI_API_KEY",
  "COPILOT_PROVIDER_API_KEY",
  "COPILOT_PROVIDER_BASE_URL",
  "COPILOT_PROVIDER_TYPE",
] as const;

export const providerBinaries: Record<ProviderId, string> = {
  "claude-code": "claude",
  codex: "codex",
  cursor: "agent",
  copilot: "copilot",
};

export const providerLabels: Record<ProviderId, string> = {
  "claude-code": "Claude Code",
  codex: "Codex",
  cursor: "Cursor",
  copilot: "GitHub Copilot",
};

export const billingLabels: Record<BillingType, string> = {
  "personal-subscription": "Assinatura pessoal",
  "corporate-subscription": "Assinatura corporativa",
  "metered-api": "API com cobrança por utilização",
  "provider-credits": "Créditos do provedor",
  unmetered: "Sem contabilização do provedor",
};

export const modeLabels: Record<OperationMode, string> = {
  economic: "Econômico",
  balanced: "Equilibrado",
  restricted: "Restrito",
};

export const usageUnitLabels: Record<UsageUnit, string> = {
  "app-tokens": "Tokens desta aplicação",
  "provider-credits": "Créditos do provedor",
  "estimated-usd": "Custo estimado",
  "provider-quota": "Quota informada pelo provedor",
};

export interface ModelDefinition {
  id: string;
  provider: ProviderId;
  name: string;
  modelClass: ModelClass;
  enabled: boolean;
  cliAlias: string | null;
}

export interface IntegrationAccount {
  id: string;
  provider: ProviderId;
  label: string;
  billingType: BillingType | null;
  authState: AuthState;
  availability: Availability;
  detectedApiKey: boolean;
  meteredAuthorized: boolean;
  configured: boolean;
  authorizedModelIds: string[];
  cliInstalled: boolean;
}

export interface ScopePolicy {
  scope: PolicyScope;
  scopeId: string;
  accountId: string;
  decision: PolicyDecision;
}

export interface ConsumptionGrant {
  executionId: string;
  accountId: string;
  modelId: string;
  kind: "once" | "until-limit";
  limitAmount?: number;
  consumedAmount?: number;
  result: "approved" | "denied";
}

export interface PlanAgent {
  role: AgentRole;
  accountId: string;
  modelId: string;
}

export interface ExecutionPlan {
  phases: Phase[];
  agents: PlanAgent[];
  boundAccountIds: string[];
  sameAccount: true;
}

export interface ModelOption {
  id: string;
  name: string;
  accountId: string;
}

export type StartDecision =
  | {
      outcome: "ready";
      plan: ExecutionPlan;
      message: string;
    }
  | {
      outcome: "awaiting-authorization";
      plan: ExecutionPlan;
      prompt: string;
      accountId: string;
      modelId: string;
      billingLabel: string;
      alternativeModels: ModelOption[];
    }
  | {
      outcome: "block";
      code: BlockCode;
      message: string;
    }
  | {
      outcome: "pause-team";
      code: "quota" | "unavailable";
      message: string;
      preserveSession: true;
      alternatives: ModelOption[];
    };

export type BlockCode =
  | "unauthenticated"
  | "disconnected"
  | "not-authorized"
  | "model-denied"
  | "metered-blocked"
  | "unproven-availability"
  | "premium-disabled"
  | "no-economy-model"
  | "forbidden"
  | "choose-account";

export interface ObservedUsage {
  unit: UsageUnit;
  amount: number | null;
  source: "app" | "provider" | "estimate";
}

export function emptyUsage(): ObservedUsage[] {
  return [
    { unit: "app-tokens", amount: null, source: "app" },
    { unit: "provider-credits", amount: null, source: "provider" },
    { unit: "estimated-usd", amount: null, source: "estimate" },
    { unit: "provider-quota", amount: null, source: "provider" },
  ];
}
