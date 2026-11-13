import { realpathSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import {
  assertLocalOperator,
  detectMeteredEnv,
  evaluateStart,
  OperatorError,
  pauseTeam,
  decideResume,
  resolveCatalog,
  type EvaluateInput,
} from "@ai-workforce/authorization";
import {
  emptyUsage,
  events,
  LOCAL_OPERATOR,
  providerLabels,
  type ApprovalCategory,
  type ApprovalMode,
  type Availability,
  type BillingType,
  type Complexity,
  type ExecutionPlan,
  type IntegrationAccount,
  type OperationMode,
  type PolicyDecision,
  type StartDecision,
} from "@ai-workforce/contracts";
import { probeInstalledClis } from "./probe.js";
import { Repository } from "./repository.js";
import { AdapterNotInstalled, startProviderRun } from "./runtime.js";

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code = "bad-request",
  ) {
    super(message);
  }
}

const modes = new Set<OperationMode>(["economic", "balanced", "restricted"]);
const complexities = new Set<Complexity>(["simple", "standard", "architecture"]);
const decisions = new Set<PolicyDecision>(["allow", "allow-with-approval", "deny"]);
const billing = new Set<BillingType>([
  "personal-subscription",
  "corporate-subscription",
  "metered-api",
  "provider-credits",
  "unmetered",
]);

let emit: (event: unknown) => void = () => {};

export function setEventPublisher(publisher: (event: unknown) => void): void {
  emit = publisher;
}

function publish(type: string, payload: unknown): void {
  emit({ type, payload, at: new Date().toISOString() });
}

export function createService(repo: Repository) {
  function models() {
    return resolveCatalog(repo.overrides());
  }

  function accountsFor(workspaceId: string): IntegrationAccount[] {
    const detected = detectMeteredEnv(process.env);
    const installed = probeInstalledClis();
    return repo.accounts().map((account) => ({
      ...account,
      authorizedModelIds: repo.modelIds("workspace", workspaceId, account.id),
      detectedApiKey: account.detectedApiKey || detected[account.provider],
      cliInstalled: installed[account.provider],
    }));
  }

  function requireOperator(actor: string | undefined): void {
    try {
      assertLocalOperator(actor ?? "");
    } catch (error) {
      if (error instanceof OperatorError) throw new HttpError(403, error.message, "agent-forbidden");
      throw error;
    }
  }

  function scopePolicies(workspaceId: string, projectId?: string) {
    const ids = ["org-local", workspaceId];
    if (projectId) ids.push(projectId);
    return repo.policiesFor(ids);
  }

  function applyReady(executionId: string, taskId: string, decision: Extract<StartDecision, { outcome: "ready" }>): void {
    try {
      startProviderRun();
    } catch (error) {
      if (!(error instanceof AdapterNotInstalled)) throw error;
      repo.updateExecution(executionId, { status: "awaiting-availability", interruptionReason: error.message });
      repo.updateTaskStatus(taskId, "awaiting-availability");
      repo.addEvent(executionId, events.executionStateChanged, {
        status: "awaiting-availability",
        message: error.message,
        plan: decision.plan,
      });
      publish(events.executionStateChanged, { executionId, status: "awaiting-availability" });
    }
  }

  function persistDecision(input: {
    taskId: string;
    executionId?: string;
    decision: StartDecision;
    actor: string;
  }): string {
    const plan = "plan" in input.decision ? input.decision.plan : null;
    const lead = plan?.agents[0];
    const provider = lead ? repo.account(lead.accountId)?.provider ?? null : null;

    if (!input.executionId) {
      const created = repo.insertExecution({
        taskId: input.taskId,
        accountId: lead?.accountId ?? null,
        modelId: lead?.modelId ?? null,
        status:
          input.decision.outcome === "ready"
            ? "ready"
            : input.decision.outcome === "awaiting-authorization"
              ? "awaiting-authorization"
              : input.decision.outcome === "pause-team"
                ? "paused-by-limit"
                : "blocked",
        planJson: plan ? JSON.stringify(plan) : null,
        interruptionReason: input.decision.outcome === "ready" ? null : decisionText(input.decision),
      });
      input.executionId = created.id;
    } else if (plan) {
      repo.updateExecution(input.executionId, {
        planJson: JSON.stringify(plan),
        accountId: lead?.accountId ?? null,
        modelId: lead?.modelId ?? null,
      });
    }

    const executionId = input.executionId;
    const detail = decisionText(input.decision);
    repo.audit({
      actor: input.actor,
      action: "usage.evaluate",
      provider,
      modelId: lead?.modelId ?? null,
      accountId: lead?.accountId ?? null,
      result: input.decision.outcome,
      detail,
    });

    if (input.decision.outcome === "block") {
      repo.updateExecution(executionId, { status: "blocked", interruptionReason: input.decision.message });
      repo.updateTaskStatus(input.taskId, "blocked");
      repo.addEvent(executionId, events.executionStateChanged, { status: "blocked", code: input.decision.code, message: input.decision.message });
    } else if (input.decision.outcome === "pause-team") {
      repo.updateExecution(executionId, { status: "paused-by-limit", interruptionReason: input.decision.message });
      repo.updateTaskStatus(input.taskId, "paused");
      repo.addEvent(executionId, events.quotaExhausted, {
        message: input.decision.message,
        alternatives: input.decision.alternatives,
      });
      publish(events.quotaExhausted, { executionId, message: input.decision.message });
    } else if (input.decision.outcome === "awaiting-authorization") {
      repo.updateExecution(executionId, {
        status: "awaiting-authorization",
        interruptionReason: input.decision.prompt,
        accountId: input.decision.accountId,
        modelId: input.decision.modelId,
      });
      repo.updateTaskStatus(input.taskId, "awaiting-authorization");
      const existing = repo.pendingApprovalForExecution(executionId);
      if (!existing) {
        repo.insertApproval({
          executionId,
          taskId: input.taskId,
          prompt: input.decision.prompt,
          accountId: input.decision.accountId,
          modelId: input.decision.modelId,
          alternatives: input.decision.alternativeModels,
        });
      }
      repo.addEvent(executionId, events.authorizationRequested, {
        prompt: input.decision.prompt,
        accountId: input.decision.accountId,
        modelId: input.decision.modelId,
      });
      publish(events.authorizationRequested, { executionId, taskId: input.taskId });
    } else {
      applyReady(executionId, input.taskId, input.decision);
    }
    return executionId;
  }

  return {
    snapshot() {
      const installed = probeInstalledClis();
      const detected = detectMeteredEnv(process.env);
      return {
        organization: repo.organization(),
        workspaces: repo.listWorkspaces(),
        integrations: repo.accounts().map((account) => ({
          ...account,
          detectedApiKey: account.detectedApiKey || detected[account.provider],
          cliInstalled: installed[account.provider],
          usage: emptyUsage(),
          availabilityLabel: availabilityLabel(account.availability),
        })),
        models: models(),
        tasks: repo.recentTasks(),
        approvals: repo.pendingApprovals(),
        approvalPolicies: repo.approvalPolicies(),
        audit: repo.recentAudit(),
      };
    },

    setMode(actor: string | undefined, mode: OperationMode) {
      requireOperator(actor);
      if (!modes.has(mode)) throw new HttpError(400, "Modo de operação desconhecido.");
      repo.setMode(mode);
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "organization.mode",
        result: "updated",
        detail: `Modo global definido como ${mode}.`,
      });
      return repo.organization();
    },

    createWorkspace(actor: string | undefined, name: string) {
      requireOperator(actor);
      const trimmed = name.trim();
      if (!trimmed) throw new HttpError(400, "Informe o nome do workspace.");
      const workspace = repo.insertWorkspace(trimmed);
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "workspace.create",
        result: "created",
        detail: `Workspace ${workspace.name} criado.`,
      });
      return workspace;
    },

    workspaceView(id: string) {
      const workspace = repo.workspace(id);
      if (!workspace) throw new HttpError(404, "Workspace não encontrado.");
      return {
        workspace,
        projects: repo.listProjects(id),
        tasks: repo.tasksByWorkspace(id),
        policies: repo.accounts().map((account) => ({
          accountId: account.id,
          provider: account.provider,
          label: account.label,
          billingType: account.billingType,
          decision: repo.policiesFor([id]).find((policy) => policy.accountId === account.id)?.decision ?? null,
          authorizedModelIds: repo.modelIds("workspace", id, account.id),
          meteredAuthorized: account.meteredAuthorized,
          configured: account.configured,
        })),
        budget: repo.budget(id),
      };
    },

    savePolicy(
      actor: string | undefined,
      workspaceId: string,
      accountId: string,
      input: {
        decision: PolicyDecision;
        billingType: BillingType | null;
        label: string;
        authorizedModelIds: string[];
        meteredAuthorized: boolean;
      },
    ) {
      requireOperator(actor);
      const workspace = repo.workspace(workspaceId);
      if (!workspace) throw new HttpError(404, "Workspace não encontrado.");
      const account = repo.account(accountId);
      if (!account) throw new HttpError(404, "Integração não encontrada.");
      if (!decisions.has(input.decision)) throw new HttpError(400, "Decisão de política inválida.");
      if (input.billingType && !billing.has(input.billingType)) throw new HttpError(400, "Tipo de cobrança inválido.");
      const catalog = models();
      const unknown = input.authorizedModelIds.filter((modelId) => !catalog.some((model) => model.id === modelId && model.provider === account.provider));
      if (unknown.length > 0) throw new HttpError(400, "Há modelos que não pertencem a esta integração.");
      repo.transaction(() => {
        repo.updateAccount({
          id: accountId,
          label: input.label.trim() || account.label,
          billingType: input.billingType,
          meteredAuthorized: input.meteredAuthorized,
        });
        repo.upsertPolicy("workspace", workspaceId, accountId, input.decision);
        repo.replaceModelGrants("workspace", workspaceId, accountId, input.authorizedModelIds);
        repo.audit({
          actor: actor ?? LOCAL_OPERATOR,
          action: "policy.save",
          provider: account.provider,
          accountId,
          result: input.decision,
          limitApproved: input.meteredAuthorized ? "cobrança medida autorizada" : "cobrança medida bloqueada",
          detail: `Política do workspace ${workspace.name} para ${providerLabels[account.provider]}.`,
        });
      });
      return this.workspaceView(workspaceId);
    },

    setBudget(actor: string | undefined, workspaceId: string, limitAmount: number | null) {
      requireOperator(actor);
      if (!repo.workspace(workspaceId)) throw new HttpError(404, "Workspace não encontrado.");
      if (limitAmount === null) {
        repo.clearBudget(workspaceId);
      } else if (!Number.isFinite(limitAmount) || limitAmount <= 0) {
        throw new HttpError(400, "O teto precisa ser um número maior que zero.");
      } else {
        repo.setBudget(workspaceId, limitAmount);
      }
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "budget.set",
        result: limitAmount === null ? "cleared" : "updated",
        limitApproved: limitAmount === null ? null : String(limitAmount),
        detail: "Teto de tokens observados nesta aplicação.",
      });
      return repo.budget(workspaceId);
    },

    createProject(actor: string | undefined, workspaceId: string, name: string, projectPath: string) {
      requireOperator(actor);
      if (!repo.workspace(workspaceId)) throw new HttpError(404, "Workspace não encontrado.");
      const trimmed = name.trim();
      if (!trimmed) throw new HttpError(400, "Informe o nome do projeto.");
      if (!isAbsolute(projectPath)) throw new HttpError(400, "O caminho do projeto precisa ser absoluto.");
      let resolved: string;
      try {
        const stat = statSync(projectPath);
        if (!stat.isDirectory()) throw new HttpError(400, "O caminho precisa ser um diretório.");
        resolved = realpathSync(projectPath);
      } catch (error) {
        if (error instanceof HttpError) throw error;
        throw new HttpError(400, "O diretório do projeto não existe.");
      }
      const project = repo.insertProject(workspaceId, trimmed, resolved);
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "project.create",
        result: "created",
        detail: `Projeto ${project.name} registrado em ${project.path}. O código não foi analisado.`,
      });
      return project;
    },

    projectView(id: string) {
      const project = repo.project(id);
      if (!project) throw new HttpError(404, "Projeto não encontrado.");
      const tasks = repo.tasksByWorkspace(project.workspaceId).filter((task) => task.projectId === id);
      return { project, tasks };
    },

    createTask(
      actor: string | undefined,
      projectId: string,
      input: {
        title: string;
        complexity: Complexity;
        relevantOperation?: boolean;
        destructive?: boolean;
        accountId?: string;
        modelId?: string;
      },
    ) {
      requireOperator(actor);
      const project = repo.project(projectId);
      if (!project) throw new HttpError(404, "Projeto não encontrado.");
      const title = input.title.trim();
      if (!title) throw new HttpError(400, "Informe a tarefa.");
      if (!complexities.has(input.complexity)) throw new HttpError(400, "Complexidade inválida.");
      const workspace = repo.workspace(project.workspaceId);
      if (!workspace) throw new HttpError(404, "Workspace não encontrado.");
      const budget = repo.budget(project.workspaceId);
      const mode = repo.organization().mode;
      if (budget && mode === "restricted") {
        throw new HttpError(
          409,
          "Há um teto configurado e nenhuma estimativa do provedor. O modo restrito não inicia consumo desconhecido.",
          "unproven-availability",
        );
      }

      const task = repo.transaction(() => {
        const created = repo.insertTask({
          workspaceId: project.workspaceId,
          projectId: project.id,
          title,
          complexity: input.complexity,
          relevant: Boolean(input.relevantOperation) || Boolean(budget),
          destructive: Boolean(input.destructive),
          status: "open",
        });
        const execution = repo.insertExecution({
          taskId: created.id,
          accountId: input.accountId ?? null,
          modelId: input.modelId ?? null,
          status: "ready",
          planJson: null,
          interruptionReason: null,
        });
        const decision = evaluateStart(
          evaluationInput(repo, project.workspaceId, project.id, execution.id, created, input.accountId, input.modelId),
        );
        persistDecision({ taskId: created.id, executionId: execution.id, decision, actor: actor ?? LOCAL_OPERATOR });
        return created;
      });
      return this.taskView(task.id);
    },

    taskView(id: string) {
      const task = repo.task(id);
      if (!task) throw new HttpError(404, "Tarefa não encontrada.");
      const executions = repo.executionsForTask(id).map((execution) => ({
        ...execution,
        plan: execution.planJson ? (JSON.parse(execution.planJson) as ExecutionPlan) : null,
        events: repo.events(execution.id),
        approval: repo.pendingApprovalForExecution(execution.id) ?? null,
      }));
      return { task, executions };
    },

    decideApproval(
      actor: string | undefined,
      approvalId: string,
      input: { action: "once" | "until-limit" | "deny" | "choose-model"; modelId?: string; limitAmount?: number },
    ) {
      requireOperator(actor);
      const approval = repo.approval(approvalId);
      if (!approval || approval.status !== "pending") throw new HttpError(404, "Autorização não encontrada.");
      const task = repo.task(approval.taskId);
      const execution = repo.execution(approval.executionId);
      if (!task || !execution) throw new HttpError(404, "Execução não encontrada.");

      if (input.action === "deny") {
        repo.decideApproval(approval.id, "deny", null, "denied");
        repo.updateExecution(execution.id, { status: "cancelled", interruptionReason: "Autorização negada pelo operador." });
        repo.updateTaskStatus(task.id, "cancelled");
        repo.audit({
          actor: actor ?? LOCAL_OPERATOR,
          action: "usage.authorization.decided",
          accountId: approval.accountId,
          modelId: approval.modelId,
          result: "denied",
          detail: "O operador negou esta execução.",
        });
        repo.addEvent(execution.id, events.authorizationDecided, { result: "denied" });
        publish(events.authorizationDecided, { executionId: execution.id, result: "denied" });
        return this.taskView(task.id);
      }

      if (input.action === "until-limit" && (!input.limitAmount || input.limitAmount <= 0)) {
        throw new HttpError(400, "Informe o limite aprovado.");
      }

      const requestedModelId = input.action === "choose-model" ? input.modelId : execution.modelId ?? approval.modelId;
      if (input.action === "choose-model" && !requestedModelId) throw new HttpError(400, "Escolha um modelo autorizado.");

      if (input.action !== "choose-model") {
        const plan = execution.planJson ? (JSON.parse(execution.planJson) as ExecutionPlan) : null;
        const modelIds = new Set((plan?.agents ?? []).map((agent) => agent.modelId));
        modelIds.add(approval.modelId);
        for (const modelId of modelIds) {
          repo.insertGrant({
            executionId: execution.id,
            accountId: approval.accountId,
            modelId,
            kind: input.action === "until-limit" ? "until-limit" : "once",
            limitAmount: input.limitAmount,
          });
        }
      }

      repo.decideApproval(approval.id, input.action, input.limitAmount ?? null, "approved");
      const decision = evaluateStart(
        evaluationInput(repo, task.workspaceId, task.projectId, execution.id, task, execution.accountId ?? undefined, requestedModelId ?? undefined),
      );
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "usage.authorization.decided",
        accountId: approval.accountId,
        modelId: requestedModelId,
        limitApproved: input.limitAmount ? String(input.limitAmount) : input.action,
        result: "approved",
        detail: approval.prompt,
      });
      persistDecision({ taskId: task.id, executionId: execution.id, decision, actor: actor ?? LOCAL_OPERATOR });
      return this.taskView(task.id);
    },

    pauseTask(actor: string | undefined, taskId: string) {
      requireOperator(actor);
      const task = repo.task(taskId);
      if (!task) throw new HttpError(404, "Tarefa não encontrada.");
      for (const execution of repo.executionsForTask(taskId)) {
        if (execution.status === "cancelled" || execution.status === "blocked") continue;
        repo.updateExecution(execution.id, { status: "paused-by-user", interruptionReason: "Pausada pelo operador." });
        repo.addEvent(execution.id, events.executionStateChanged, { status: "paused-by-user" });
      }
      repo.updateTaskStatus(taskId, "paused");
      repo.audit({ actor: actor ?? LOCAL_OPERATOR, action: "execution.pause", result: "paused-by-user", detail: task.title });
      return this.taskView(taskId);
    },

    resumeTask(actor: string | undefined, taskId: string, confirmNew: boolean) {
      requireOperator(actor);
      const task = repo.task(taskId);
      if (!task) throw new HttpError(404, "Tarefa não encontrada.");
      const execution = repo.executionsForTask(taskId).at(-1);
      if (!execution) throw new HttpError(404, "Execução não encontrada.");
      const decision = decideResume(execution);
      if (decision.outcome === "reject") throw new HttpError(409, decision.message);
      if (decision.outcome === "same-session") {
        repo.addEvent(execution.id, events.resumeRequested, { sessionId: decision.sessionId, applied: false });
        return {
          task: this.taskView(taskId),
          resume: {
            outcome: "same-session" as const,
            applied: false,
            label: decision.label,
            message: `A sessão ${decision.sessionId} permanece registrada. O adaptador desta versão não a retomou e nenhuma execução nova foi criada.`,
          },
        };
      }
      if (!confirmNew) {
        repo.addEvent(execution.id, events.resumeRejected, { message: decision.message });
        return { task: this.taskView(taskId), resume: { outcome: "new-execution" as const, applied: false, label: decision.label, message: decision.message } };
      }
      const created = repo.insertExecution({
        taskId,
        accountId: execution.accountId,
        modelId: execution.modelId,
        status: "ready",
        planJson: null,
        interruptionReason: null,
        resumeKind: "nova execução",
      });
      const next = evaluateStart(
        evaluationInput(repo, task.workspaceId, task.projectId, created.id, task, execution.accountId ?? undefined, execution.modelId ?? undefined),
      );
      persistDecision({ taskId, executionId: created.id, decision: next, actor: actor ?? LOCAL_OPERATOR });
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "execution.resume",
        result: "nova execução",
        detail: "A sessão original não pôde ser retomada. Foi criada uma execução nova.",
      });
      return {
        task: this.taskView(taskId),
        resume: {
          outcome: "new-execution" as const,
          applied: true,
          label: "nova execução" as const,
          message: "Esta execução é nova. Ela não é uma retomada da sessão anterior.",
        },
      };
    },

    enablePremium(actor: string | undefined, modelId: string, enabled: boolean) {
      requireOperator(actor);
      if (modelId !== "claude-fable" && modelId !== "cursor-third-party") {
        throw new HttpError(400, "Só Fable e modelos de terceiro do Cursor exigem esta habilitação.");
      }
      repo.setOverride(modelId, enabled);
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "model.premium",
        modelId,
        result: enabled ? "enabled" : "disabled",
        detail: enabled ? "Habilitação explícita de modelo premium." : "Modelo premium desabilitado.",
      });
      return models();
    },

    setApprovalPolicy(actor: string | undefined, category: ApprovalCategory, mode: ApprovalMode) {
      requireOperator(actor);
      repo.setApprovalMode(category, mode);
      repo.audit({
        actor: actor ?? LOCAL_OPERATOR,
        action: "approval.policy",
        result: mode,
        detail: `Categoria ${category}.`,
      });
      return repo.approvalPolicies();
    },

    recordProviderFact(accountId: string, availability: Availability, authState: "authenticated" | "unauthenticated" | "disconnected") {
      if (!repo.account(accountId)) throw new HttpError(404, "Integração não encontrada.");
      repo.setAvailability(accountId, availability, authState);
      publish(events.availabilityChanged, { accountId, availability, authState });
    },

    signalQuota(accountId: string) {
      const account = repo.account(accountId);
      if (!account) throw new HttpError(404, "Integração não encontrada.");
      repo.setAvailability(accountId, "quota-exhausted", account.authState);
      const open = repo.recentTasks(100).flatMap((task) =>
        repo.executionsForTask(task.id).map((execution) => ({
          id: execution.id,
          taskId: execution.taskId,
          accountId: execution.accountId ?? "",
          status: execution.status,
          sessionId: execution.sessionId,
        })),
      );
      const paused = pauseTeam({
        mode: repo.organization().mode,
        accountId,
        reason: "quota-exhausted",
        executions: open,
        accounts: repo.accounts().map((item) => ({
          ...item,
          authorizedModelIds: [],
          cliInstalled: false,
        })),
        models: models(),
        policies: [],
      });
      for (const executionId of paused.executionIds) {
        repo.updateExecution(executionId, { status: "paused-by-limit", interruptionReason: paused.message });
        repo.addEvent(executionId, events.quotaExhausted, { message: paused.message });
        const execution = repo.execution(executionId);
        if (execution) repo.updateTaskStatus(execution.taskId, "paused");
      }
      publish(events.quotaExhausted, { accountId, message: paused.message });
      return paused;
    },
  };
}

function evaluationInput(
  repo: Repository,
  workspaceId: string,
  projectId: string,
  executionId: string,
  task: { complexity: Complexity; relevant: boolean; destructive: boolean },
  accountId?: string,
  modelId?: string,
): EvaluateInput {
  const workspace = repo.workspace(workspaceId);
  const detected = detectMeteredEnv(process.env);
  const installed = probeInstalledClis();
  return {
    mode: repo.organization().mode,
    executionId,
    complexity: task.complexity,
    relevantOperation: task.relevant,
    destructive: task.destructive,
    consumptionPolicy: repo.approvalMode("consumption"),
    accounts: repo.accounts().map((account) => ({
      ...account,
      authorizedModelIds: repo.modelIds("workspace", workspaceId, account.id),
      detectedApiKey: account.detectedApiKey || detected[account.provider],
      cliInstalled: installed[account.provider],
    })),
    models: resolveCatalog(repo.overrides()),
    policies: repo.policiesFor(["org-local", workspaceId, projectId]),
    grants: repo.grantsFor(executionId).map((grant) => ({
      executionId: grant.executionId,
      accountId: grant.accountId,
      modelId: grant.modelId,
      kind: grant.kind,
      result: "approved" as const,
      ...(grant.limitAmount === null ? {} : { limitAmount: grant.limitAmount }),
      ...(grant.consumedAmount === null ? {} : { consumedAmount: grant.consumedAmount }),
    })),
    agentLimit: workspace?.agentLimit ?? 1,
    ...(accountId ? { requestedAccountId: accountId } : {}),
    ...(modelId ? { requestedModelId: modelId } : {}),
  };
}

function decisionText(decision: StartDecision): string {
  return decision.outcome === "awaiting-authorization" ? decision.prompt : decision.message;
}

function availabilityLabel(availability: Availability): string {
  switch (availability) {
    case "not-probed":
      return "Não verificada";
    case "unknown":
      return "Desconhecida";
    case "available":
      return "Disponível";
    case "quota-exhausted":
      return "Limite atingido";
    case "disconnected":
      return "Desconectada";
    case "unauthenticated":
      return "Sem autenticação";
    case "restricted":
      return "Restrita";
  }
}

export type WorkforceService = ReturnType<typeof createService>;
