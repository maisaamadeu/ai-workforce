import {
  billingLabels,
  providerLabels,
  type AgentRole,
  type ApprovalMode,
  type Complexity,
  type ConsumptionGrant,
  type ExecutionPlan,
  type ExecutionStatus,
  type IntegrationAccount,
  type ModelClass,
  type ModelDefinition,
  type ModelOption,
  type OperationMode,
  type Phase,
  type PlanAgent,
  type PolicyDecision,
  type PolicyScope,
  type ScopePolicy,
  type StartDecision,
} from "@ai-workforce/contracts";

const scopeRank: Record<PolicyScope, number> = {
  organization: 0,
  workspace: 1,
  project: 2,
  agent: 3,
  execution: 4,
};

const phases: Phase[] = ["analyze", "plan", "implement", "review"];

const classRank: Record<ModelClass, number> = {
  economy: 0,
  standard: 1,
  reasoning: 2,
  "explicit-premium": 3,
};

export class OperatorError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OperatorError";
  }
}

export function assertLocalOperator(actor: string): void {
  if (actor !== "local-operator") {
    throw new OperatorError(
      "Um agente não pode autorizar operações, alterar permissões ou aumentar o orçamento.",
    );
  }
}

export interface EvaluateInput {
  mode: OperationMode;
  executionId: string;
  complexity: Complexity;
  relevantOperation: boolean;
  destructive: boolean;
  consumptionPolicy: ApprovalMode;
  accounts: IntegrationAccount[];
  models: ModelDefinition[];
  policies: ScopePolicy[];
  grants: ConsumptionGrant[];
  requestedAccountId?: string;
  requestedModelId?: string;
  agentLimit?: number;
}

export interface TeamExecution {
  id: string;
  taskId: string;
  accountId: string;
  status: ExecutionStatus;
  sessionId: string | null;
}

export interface PauseTeamInput {
  mode: OperationMode;
  accountId: string;
  reason: "quota-exhausted" | "disconnected" | "restricted" | "unavailable";
  executions: TeamExecution[];
  accounts: IntegrationAccount[];
  models: ModelDefinition[];
  policies: ScopePolicy[];
}

export interface PauseTeamResult {
  outcome: "pause-team";
  message: string;
  preserveSession: true;
  executionIds: string[];
  taskIds: string[];
  alternatives: ModelOption[];
}

export type ResumeDecision =
  | { outcome: "same-session"; sessionId: string; label: "retomada" }
  | { outcome: "new-execution"; label: "nova execução"; message: string }
  | { outcome: "reject"; message: string };

function resolvePolicy(accountId: string, policies: ScopePolicy[]): PolicyDecision | "absent" {
  const applicable = policies
    .filter((policy) => policy.accountId === accountId)
    .slice()
    .sort((left, right) => scopeRank[left.scope] - scopeRank[right.scope]);
  let current: PolicyDecision | "absent" = "absent";
  for (const policy of applicable) {
    if (policy.decision === "deny") {
      current = "deny";
      continue;
    }
    if (current === "deny" || current === "absent") {
      if (current === "deny") continue;
      current = policy.decision;
      continue;
    }
    if (policy.decision === "allow-with-approval") current = "allow-with-approval";
  }
  return current;
}

function classAllowed(mode: OperationMode, modelClass: ModelClass): boolean {
  if (modelClass === "explicit-premium") return false;
  if (mode === "economic") return modelClass === "economy";
  if (mode === "restricted") return modelClass === "economy" || modelClass === "standard" || modelClass === "reasoning";
  return modelClass === "economy" || modelClass === "standard" || modelClass === "reasoning";
}

function eligibleModels(
  account: IntegrationAccount,
  mode: OperationMode,
  models: readonly ModelDefinition[],
  requestedModelId?: string,
): ModelDefinition[] {
  return models
    .filter((model) => {
      if (model.provider !== account.provider || !model.enabled) return false;
      if (!account.authorizedModelIds.includes(model.id)) return false;
      if (model.modelClass === "explicit-premium") {
        return requestedModelId === model.id && mode !== "economic";
      }
      return classAllowed(mode, model.modelClass);
    })
    .sort((left, right) => classRank[left.modelClass] - classRank[right.modelClass] || left.name.localeCompare(right.name));
}

function pickModel(models: ModelDefinition[], complexity: Complexity, mode: OperationMode): ModelDefinition | undefined {
  if (mode === "economic") return models.find((model) => model.modelClass === "economy");
  if (complexity === "architecture") {
    return (
      models.find((model) => model.modelClass === "reasoning") ??
      models.find((model) => model.modelClass === "standard") ??
      models.find((model) => model.modelClass === "economy")
    );
  }
  if (complexity === "standard") {
    return (
      models.find((model) => model.modelClass === "standard") ??
      models.find((model) => model.modelClass === "economy") ??
      models.find((model) => model.modelClass === "reasoning")
    );
  }
  return (
    models.find((model) => model.modelClass === "economy") ??
    models.find((model) => model.modelClass === "standard") ??
    models.find((model) => model.modelClass === "reasoning")
  );
}

function modelByClass(models: ModelDefinition[], modelClass: ModelClass): ModelDefinition | undefined {
  return models.find((model) => model.modelClass === modelClass);
}

function buildPlan(
  mode: OperationMode,
  complexity: Complexity,
  account: IntegrationAccount,
  models: ModelDefinition[],
  agentLimit: number,
): ExecutionPlan | { code: "no-economy-model"; message: string } {
  if (mode === "economic") {
    const economy = models.find((model) => model.modelClass === "economy");
    if (!economy) {
      return {
        code: "no-economy-model",
        message: "Nenhum modelo econômico está autorizado nesta conta. Autorize um modelo econômico ou mude o modo de operação.",
      };
    }
    return {
      phases,
      sameAccount: true,
      boundAccountIds: [account.id],
      agents: [{ role: "executor", accountId: account.id, modelId: economy.id }],
    };
  }

  const lead = pickModel(models, complexity, mode) ?? models[0];
  if (!lead) {
    return {
      code: "no-economy-model",
      message: "Nenhum modelo autorizado nesta conta cabe no modo de operação atual.",
    };
  }

  let agents: PlanAgent[];
  if (complexity === "simple" || agentLimit < 2) {
    agents = [{ role: "executor", accountId: account.id, modelId: lead.id }];
  } else if (complexity === "standard") {
    const standardTeam: PlanAgent[] = [
      { role: "developer", accountId: account.id, modelId: (modelByClass(models, "standard") ?? lead).id },
      { role: "reviewer", accountId: account.id, modelId: (modelByClass(models, "economy") ?? lead).id },
    ];
    agents = standardTeam.slice(0, agentLimit);
  } else {
    const architect = modelByClass(models, "reasoning") ?? lead;
    const developer = modelByClass(models, "standard") ?? lead;
    const reviewer = modelByClass(models, "economy") ?? modelByClass(models, "standard") ?? lead;
    const architectureTeam: PlanAgent[] = [
      { role: "architect", accountId: account.id, modelId: architect.id },
      { role: "developer", accountId: account.id, modelId: developer.id },
      { role: "reviewer", accountId: account.id, modelId: reviewer.id },
    ];
    agents = architectureTeam.slice(0, agentLimit);
  }

  return {
    phases,
    sameAccount: true,
    boundAccountIds: [account.id],
    agents,
  };
}

function grantCovers(grants: ConsumptionGrant[], executionId: string, accountId: string, modelId: string): boolean {
  return grants.some((grant) => {
    if (grant.executionId !== executionId || grant.accountId !== accountId || grant.modelId !== modelId) return false;
    if (grant.result !== "approved") return false;
    if (grant.kind === "once") return true;
    const limit = grant.limitAmount ?? 0;
    const consumed = grant.consumedAmount ?? 0;
    return consumed < limit;
  });
}

function needsApproval(input: EvaluateInput, decision: PolicyDecision, plan: ExecutionPlan, availabilityUnproven: boolean): boolean {
  if (input.consumptionPolicy === "forbidden") return true;
  if (decision === "allow-with-approval") return true;
  if (availabilityUnproven && input.mode !== "restricted") return true;
  if (input.mode === "economic") {
    return input.relevantOperation || input.destructive || input.complexity === "architecture" || plan.agents.length > 1;
  }
  if (input.mode === "balanced") return input.relevantOperation || input.destructive;
  return false;
}

function alternativesFor(
  excludedAccountId: string,
  input: Pick<EvaluateInput, "mode" | "accounts" | "models" | "policies" | "complexity">,
): ModelOption[] {
  if (input.mode === "restricted") return [];
  const options: ModelOption[] = [];
  for (const account of input.accounts) {
    if (account.id === excludedAccountId) continue;
    if (account.billingType === "metered-api" && !account.meteredAuthorized) continue;
    if (account.authState !== "authenticated" || account.availability !== "available") continue;
    const policy = resolvePolicy(account.id, input.policies);
    if (policy !== "allow" && policy !== "allow-with-approval") continue;
    const models = eligibleModels(account, input.mode, input.models);
    const chosen = pickModel(models, input.complexity, input.mode);
    if (!chosen) continue;
    options.push({ id: chosen.id, name: chosen.name, accountId: account.id });
  }
  return options;
}

function quotaMessage(account: IntegrationAccount): string {
  if (account.billingType === "provider-credits") {
    return `${providerLabels[account.provider]} atingiu o limite de créditos disponível. A equipe foi pausada.`;
  }
  return `${providerLabels[account.provider]} atingiu o limite de utilização disponível. A equipe foi pausada.`;
}

function accountGate(account: IntegrationAccount): StartDecision | null {
  if (account.billingType === "metered-api" && !account.meteredAuthorized) {
    return {
      outcome: "block",
      code: "metered-blocked",
      message: "A API com cobrança por utilização está bloqueada. Ela não substitui a assinatura.",
    };
  }
  if (account.availability === "not-probed") return null;
  if (account.authState === "unauthenticated" || account.availability === "unauthenticated") {
    return { outcome: "block", code: "unauthenticated", message: "A integração não está autenticada." };
  }
  if (account.authState === "disconnected" || account.availability === "disconnected") {
    return { outcome: "block", code: "disconnected", message: "A integração está desconectada." };
  }
  return null;
}

export function evaluateStart(input: EvaluateInput): StartDecision {
  if (input.consumptionPolicy === "forbidden") {
    return { outcome: "block", code: "forbidden", message: "A política proíbe este tipo de consumo." };
  }

  const permitted = input.accounts.filter((account) => {
    if (account.billingType === "metered-api" && !account.meteredAuthorized) return false;
    const decision = resolvePolicy(account.id, input.policies);
    return decision === "allow" || decision === "allow-with-approval";
  });

  let account: IntegrationAccount | undefined;
  if (input.requestedAccountId) {
    account = input.accounts.find((item) => item.id === input.requestedAccountId);
    if (!account) return { outcome: "block", code: "not-authorized", message: "A conta solicitada não existe neste registro." };
    const decision = resolvePolicy(account.id, input.policies);
    if (decision === "deny" || decision === "absent") {
      return { outcome: "block", code: "not-authorized", message: "A conta não está autorizada neste escopo." };
    }
  } else if (permitted.length === 1) {
    account = permitted[0];
  } else if (permitted.length === 0) {
    return {
      outcome: "block",
      code: "not-authorized",
      message: "Nenhuma conta está autorizada neste escopo. Conectar uma integração não autoriza o consumo.",
    };
  } else {
    return {
      outcome: "block",
      code: "choose-account",
      message: "Há mais de uma conta autorizada. Escolha qual conta esta tarefa deve usar.",
    };
  }

  if (!account) {
    return { outcome: "block", code: "not-authorized", message: "Nenhuma conta está autorizada neste escopo." };
  }

  const gated = accountGate(account);
  if (gated) return gated;

  const policy = resolvePolicy(account.id, input.policies);
  if (policy === "deny" || policy === "absent") {
    return { outcome: "block", code: "not-authorized", message: "A conta não está autorizada neste escopo." };
  }

  if (input.requestedModelId) {
    const requested = input.models.find((model) => model.id === input.requestedModelId);
    if (!requested || !requested.enabled) {
      return {
        outcome: "block",
        code: "premium-disabled",
        message: "Esse modelo permanece desabilitado até uma autorização explícita.",
      };
    }
    const allowedClass =
      requested.modelClass === "explicit-premium" ? input.mode !== "economic" : classAllowed(input.mode, requested.modelClass);
    if (requested.provider !== account.provider || !account.authorizedModelIds.includes(requested.id) || !allowedClass) {
      return { outcome: "block", code: "model-denied", message: "O modelo não está autorizado neste workspace para o modo atual." };
    }
  }

  const usable = eligibleModels(account, input.mode, input.models, input.requestedModelId);
  const planResult = buildPlan(input.mode, input.complexity, account, usable, input.agentLimit ?? 4);
  if ("code" in planResult) {
    return { outcome: "block", code: planResult.code, message: planResult.message };
  }
  const plan = planResult;
  if (input.requestedModelId) {
    plan.agents = plan.agents.map((agent) => ({ ...agent, modelId: input.requestedModelId as string }));
  }

  if (account.availability === "quota-exhausted" || account.availability === "restricted") {
    return {
      outcome: "pause-team",
      code: "quota",
      message: quotaMessage(account),
      preserveSession: true,
      alternatives: alternativesFor(account.id, input),
    };
  }

  const unproven = account.availability === "unknown" || account.availability === "not-probed";
  if (unproven && input.mode === "restricted") {
    return {
      outcome: "block",
      code: "unproven-availability",
      message:
        account.availability === "not-probed"
          ? "A disponibilidade ainda não foi verificada. O modo restrito não inicia a execução."
          : "O provedor não informou a quota restante. O modo restrito não inicia a execução.",
    };
  }

  const leadModelId = plan.agents[0]?.modelId;
  if (!leadModelId) {
    return { outcome: "block", code: "no-economy-model", message: "Não há modelo utilizável nesta conta." };
  }
  const leadModel = input.models.find((model) => model.id === leadModelId);

  const approvalRequired = needsApproval(input, policy === "allow-with-approval" ? "allow-with-approval" : "allow", plan, unproven);
  const covered = plan.agents.every((agent) => grantCovers(input.grants, input.executionId, agent.accountId, agent.modelId));
  if (approvalRequired && !covered) {
    const prompt = `Esta tarefa utilizará ${leadModel?.name ?? "o modelo selecionado"} pela ${account.billingType ? billingLabels[account.billingType].toLowerCase() : "conta"} conectada (${account.label}). Deseja autorizar esta execução?`;
    return {
      outcome: "awaiting-authorization",
      plan,
      prompt,
      accountId: account.id,
      modelId: leadModelId,
      billingLabel: account.billingType ? billingLabels[account.billingType] : "Conta sem tipo de cobrança",
      alternativeModels: usable
        .filter((model) => model.id !== leadModelId)
        .map((model) => ({ id: model.id, name: model.name, accountId: account.id })),
    };
  }

  return {
    outcome: "ready",
    plan,
    message: `Plano autorizado na conta ${account.label}. Todas as fases usam essa mesma conta.`,
  };
}

export function pauseTeam(input: PauseTeamInput): PauseTeamResult {
  const account = input.accounts.find((item) => item.id === input.accountId);
  const affectedTasks = new Set(
    input.executions.filter((execution) => execution.accountId === input.accountId).map((execution) => execution.taskId),
  );
  const affected = input.executions.filter((execution) => affectedTasks.has(execution.taskId));
  const providerName = account ? providerLabels[account.provider] : "A integração";
  const message =
    input.reason === "disconnected"
      ? `${providerName} desconectou durante a execução. A equipe foi pausada e a sessão conhecida foi preservada.`
      : account && account.billingType === "provider-credits"
        ? `${providerName} atingiu o limite de créditos disponível. A equipe foi pausada.`
        : `${providerName} atingiu o limite de utilização disponível. A equipe foi pausada.`;

  return {
    outcome: "pause-team",
    message,
    preserveSession: true,
    executionIds: affected.map((execution) => execution.id),
    taskIds: [...affectedTasks],
    alternatives: account
      ? alternativesFor(account.id, {
          mode: input.mode,
          accounts: input.accounts,
          models: input.models,
          policies: input.policies,
          complexity: "standard",
        })
      : [],
  };
}

const resumable = new Set<ExecutionStatus>([
  "paused-by-user",
  "paused-by-limit",
  "awaiting-authorization",
  "awaiting-availability",
]);

export function decideResume(execution: {
  status: ExecutionStatus;
  sessionId: string | null;
  resumable: boolean;
}): ResumeDecision {
  if (!resumable.has(execution.status)) {
    return { outcome: "reject", message: "Esta execução não está pausada." };
  }
  if (execution.sessionId && execution.resumable) {
    return { outcome: "same-session", sessionId: execution.sessionId, label: "retomada" };
  }
  return {
    outcome: "new-execution",
    label: "nova execução",
    message: "Não é possível retomar a sessão original. Autorizar uma nova execução com o contexto recuperado?",
  };
}
