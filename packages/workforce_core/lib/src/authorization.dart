import 'catalog.dart';
import 'contracts.dart';

class OperatorError implements Exception {
  OperatorError(this.message);
  final String message;

  @override
  String toString() => message;
}

void assertLocalOperator(String actor) {
  if (actor != localOperator) {
    throw OperatorError(
      'Um agente não pode autorizar operações, alterar permissões ou aumentar o orçamento.',
    );
  }
}

class EvaluateInput {
  const EvaluateInput({
    required this.mode,
    required this.executionId,
    required this.complexity,
    required this.relevantOperation,
    required this.destructive,
    required this.consumptionPolicy,
    required this.accounts,
    required this.models,
    required this.policies,
    required this.grants,
    this.requestedAccountId,
    this.requestedModelId,
    this.agentLimit,
  });

  final OperationMode mode;
  final String executionId;
  final Complexity complexity;
  final bool relevantOperation;
  final bool destructive;
  final ApprovalMode consumptionPolicy;
  final List<IntegrationAccount> accounts;
  final List<ModelDefinition> models;
  final List<ScopePolicy> policies;
  final List<ConsumptionGrant> grants;
  final String? requestedAccountId;
  final String? requestedModelId;
  final int? agentLimit;
}

const _scopeRank = {
  PolicyScope.organization: 0,
  PolicyScope.workspace: 1,
  PolicyScope.project: 2,
  PolicyScope.agent: 3,
  PolicyScope.execution: 4,
};

const _phases = [Phase.analyze, Phase.plan, Phase.implement, Phase.review];

const _classRank = {
  ModelClass.economy: 0,
  ModelClass.standard: 1,
  ModelClass.reasoning: 2,
  ModelClass.explicitPremium: 3,
};

PolicyDecision? resolvePolicy(String accountId, List<ScopePolicy> policies) {
  final applicable =
      policies.where((policy) => policy.accountId == accountId).toList()..sort(
        (left, right) =>
            _scopeRank[left.scope]!.compareTo(_scopeRank[right.scope]!),
      );
  PolicyDecision? current;
  var denied = false;
  for (final policy in applicable) {
    if (policy.decision == PolicyDecision.deny) {
      denied = true;
      current = PolicyDecision.deny;
      continue;
    }
    if (denied || current == null) {
      if (denied) continue;
      current = policy.decision;
      continue;
    }
    if (policy.decision == PolicyDecision.allowWithApproval)
      current = PolicyDecision.allowWithApproval;
  }
  return current;
}

bool classAllowed(OperationMode mode, ModelClass modelClass) {
  if (modelClass == ModelClass.explicitPremium) return false;
  if (mode == OperationMode.economic) return modelClass == ModelClass.economy;
  return modelClass == ModelClass.economy ||
      modelClass == ModelClass.standard ||
      modelClass == ModelClass.reasoning;
}

List<ModelDefinition> eligibleModels(
  IntegrationAccount account,
  OperationMode mode,
  List<ModelDefinition> models, {
  String? requestedModelId,
}) {
  final eligible = models.where((model) {
    if (model.provider != account.provider || !model.enabled) return false;
    if (!account.authorizedModelIds.contains(model.id)) return false;
    if (model.modelClass == ModelClass.explicitPremium) {
      return requestedModelId == model.id && mode != OperationMode.economic;
    }
    return classAllowed(mode, model.modelClass);
  }).toList();
  eligible.sort((left, right) {
    final byClass = _classRank[left.modelClass]!.compareTo(
      _classRank[right.modelClass]!,
    );
    if (byClass != 0) return byClass;
    return left.name.compareTo(right.name);
  });
  return eligible;
}

ModelDefinition? pickModel(
  List<ModelDefinition> models,
  Complexity complexity,
  OperationMode mode,
) {
  ModelDefinition? find(ModelClass modelClass) {
    for (final model in models) {
      if (model.modelClass == modelClass) return model;
    }
    return null;
  }

  if (mode == OperationMode.economic) return find(ModelClass.economy);
  if (complexity == Complexity.architecture) {
    return find(ModelClass.reasoning) ??
        find(ModelClass.standard) ??
        find(ModelClass.economy);
  }
  if (complexity == Complexity.standard) {
    return find(ModelClass.standard) ??
        find(ModelClass.economy) ??
        find(ModelClass.reasoning);
  }
  return find(ModelClass.economy) ??
      find(ModelClass.standard) ??
      find(ModelClass.reasoning);
}

Object buildPlan(
  OperationMode mode,
  Complexity complexity,
  IntegrationAccount account,
  List<ModelDefinition> models,
  int agentLimit,
) {
  if (mode == OperationMode.economic) {
    ModelDefinition? economy;
    for (final model in models) {
      if (model.modelClass == ModelClass.economy) {
        economy = model;
        break;
      }
    }
    if (economy == null) {
      return const BlockDecision(
        code: BlockCode.noEconomyModel,
        message: 'Nenhum modelo econômico está autorizado nesta conta. Autorize um modelo econômico ou mude o modo de operação.',
      );
    }
    return ExecutionPlan(
      phases: _phases,
      boundAccountIds: [account.id],
      agents: [
        PlanAgent(
          role: AgentRole.executor,
          accountId: account.id,
          modelId: economy.id,
        ),
      ],
    );
  }

  final lead =
      pickModel(models, complexity, mode) ??
      (models.isEmpty ? null : models.first);
  if (lead == null) {
    return const BlockDecision(
      code: BlockCode.noEconomyModel,
      message: 'Nenhum modelo autorizado nesta conta cabe no modo de operação atual.',
    );
  }

  ModelDefinition? byClass(ModelClass modelClass) {
    for (final model in models) {
      if (model.modelClass == modelClass) return model;
    }
    return null;
  }

  late final List<PlanAgent> agents;
  if (complexity == Complexity.simple || agentLimit < 2) {
    agents = [
      PlanAgent(
        role: AgentRole.executor,
        accountId: account.id,
        modelId: lead.id,
      ),
    ];
  } else if (complexity == Complexity.standard) {
    agents = [
      PlanAgent(
        role: AgentRole.developer,
        accountId: account.id,
        modelId: (byClass(ModelClass.standard) ?? lead).id,
      ),
      PlanAgent(
        role: AgentRole.reviewer,
        accountId: account.id,
        modelId: (byClass(ModelClass.economy) ?? lead).id,
      ),
    ].take(agentLimit).toList();
  } else {
    final architect = byClass(ModelClass.reasoning) ?? lead;
    final developer = byClass(ModelClass.standard) ?? lead;
    final reviewer =
        byClass(ModelClass.economy) ?? byClass(ModelClass.standard) ?? lead;
    agents = [
      PlanAgent(
        role: AgentRole.architect,
        accountId: account.id,
        modelId: architect.id,
      ),
      PlanAgent(
        role: AgentRole.developer,
        accountId: account.id,
        modelId: developer.id,
      ),
      PlanAgent(
        role: AgentRole.reviewer,
        accountId: account.id,
        modelId: reviewer.id,
      ),
    ].take(agentLimit).toList();
  }

  return ExecutionPlan(
    phases: _phases,
    boundAccountIds: [account.id],
    agents: agents,
  );
}

bool grantCovers(
  List<ConsumptionGrant> grants,
  String executionId,
  String accountId,
  String modelId,
) {
  return grants.any((grant) {
    if (grant.executionId != executionId ||
        grant.accountId != accountId ||
        grant.modelId != modelId)
      return false;
    if (grant.result != 'approved') return false;
    if (grant.kind == 'once') return true;
    final limit = grant.limitAmount ?? 0;
    final consumed = grant.consumedAmount ?? 0;
    return consumed < limit;
  });
}

bool needsApproval(
  EvaluateInput input,
  PolicyDecision decision,
  ExecutionPlan plan,
  bool availabilityUnproven,
) {
  if (input.consumptionPolicy == ApprovalMode.forbidden) return true;
  if (decision == PolicyDecision.allowWithApproval) return true;
  if (availabilityUnproven && input.mode != OperationMode.restricted)
    return true;
  if (input.mode == OperationMode.economic) {
    return input.relevantOperation ||
        input.destructive ||
        input.complexity == Complexity.architecture ||
        plan.agents.length > 1;
  }
  if (input.mode == OperationMode.balanced)
    return input.relevantOperation || input.destructive;
  return false;
}

List<ModelOption> alternativesFor(
  String excludedAccountId,
  EvaluateInput input,
) {
  if (input.mode == OperationMode.restricted) return const [];
  final options = <ModelOption>[];
  for (final account in input.accounts) {
    if (account.id == excludedAccountId) continue;
    if (account.billingType == BillingType.meteredApi &&
        !account.meteredAuthorized)
      continue;
    if (account.authState != AuthState.authenticated ||
        account.availability != Availability.available)
      continue;
    final policy = resolvePolicy(account.id, input.policies);
    if (policy != PolicyDecision.allow &&
        policy != PolicyDecision.allowWithApproval)
      continue;
    final models = eligibleModels(account, input.mode, input.models);
    final chosen = pickModel(models, input.complexity, input.mode);
    if (chosen == null) continue;
    options.add(
      ModelOption(id: chosen.id, name: chosen.name, accountId: account.id),
    );
  }
  return options;
}

String quotaMessage(IntegrationAccount account) {
  if (account.billingType == BillingType.providerCredits) {
    return '${account.provider.label} atingiu o limite de créditos disponível. A equipe foi pausada.';
  }
  return '${account.provider.label} atingiu o limite de utilização disponível. A equipe foi pausada.';
}

StartDecision? accountGate(IntegrationAccount account) {
  if (account.billingType == BillingType.meteredApi &&
      !account.meteredAuthorized) {
    return const BlockDecision(
      code: BlockCode.meteredBlocked,
      message: 'A API com cobrança por utilização está bloqueada. Ela não substitui a assinatura.',
    );
  }
  if (account.availability == Availability.notProbed) return null;
  if (account.authState == AuthState.unauthenticated ||
      account.availability == Availability.unauthenticated) {
    return const BlockDecision(
      code: BlockCode.unauthenticated,
      message: 'A integração não está autenticada.',
    );
  }
  if (account.authState == AuthState.disconnected ||
      account.availability == Availability.disconnected) {
    return const BlockDecision(
      code: BlockCode.disconnected,
      message: 'A integração está desconectada.',
    );
  }
  return null;
}

StartDecision evaluateStart(EvaluateInput input) {
  if (input.consumptionPolicy == ApprovalMode.forbidden) {
    return const BlockDecision(
      code: BlockCode.forbidden,
      message: 'A política proíbe este tipo de consumo.',
    );
  }

  final permitted = input.accounts.where((account) {
    if (account.billingType == BillingType.meteredApi &&
        !account.meteredAuthorized)
      return false;
    final decision = resolvePolicy(account.id, input.policies);
    return decision == PolicyDecision.allow ||
        decision == PolicyDecision.allowWithApproval;
  }).toList();

  IntegrationAccount? account;
  if (input.requestedAccountId != null) {
    for (final item in input.accounts) {
      if (item.id == input.requestedAccountId) account = item;
    }
    if (account == null) {
      return const BlockDecision(
        code: BlockCode.notAuthorized,
        message: 'A conta solicitada não existe neste registro.',
      );
    }
    final decision = resolvePolicy(account.id, input.policies);
    if (decision == PolicyDecision.deny || decision == null) {
      return const BlockDecision(
        code: BlockCode.notAuthorized,
        message: 'A conta não está autorizada neste escopo.',
      );
    }
  } else if (permitted.length == 1) {
    account = permitted.first;
  } else if (permitted.isEmpty) {
    return const BlockDecision(
      code: BlockCode.notAuthorized,
      message: 'Nenhuma conta está autorizada neste escopo. Conectar uma integração não autoriza o consumo.',
    );
  } else {
    return const BlockDecision(
      code: BlockCode.chooseAccount,
      message: 'Há mais de uma conta autorizada. Escolha qual conta esta tarefa deve usar.',
    );
  }

  final gated = accountGate(account);
  if (gated != null) return gated;

  final policy = resolvePolicy(account.id, input.policies);
  if (policy == PolicyDecision.deny || policy == null) {
    return const BlockDecision(
      code: BlockCode.notAuthorized,
      message: 'A conta não está autorizada neste escopo.',
    );
  }

  if (input.requestedModelId != null) {
    ModelDefinition? requested;
    for (final model in input.models) {
      if (model.id == input.requestedModelId) requested = model;
    }
    if (requested == null || !requested.enabled) {
      return const BlockDecision(
        code: BlockCode.premiumDisabled,
        message:
            'Esse modelo permanece desabilitado até uma autorização explícita.',
      );
    }
    final allowedClass = requested.modelClass == ModelClass.explicitPremium
        ? input.mode != OperationMode.economic
        : classAllowed(input.mode, requested.modelClass);
    if (requested.provider != account.provider ||
        !account.authorizedModelIds.contains(requested.id) ||
        !allowedClass) {
      return const BlockDecision(
        code: BlockCode.modelDenied,
        message:
            'O modelo não está autorizado neste workspace para o modo atual.',
      );
    }
  }

  final usable = eligibleModels(
    account,
    input.mode,
    input.models,
    requestedModelId: input.requestedModelId,
  );
  final planResult = buildPlan(
    input.mode,
    input.complexity,
    account,
    usable,
    input.agentLimit ?? 4,
  );
  if (planResult is BlockDecision) return planResult;
  var plan = planResult as ExecutionPlan;
  final requestedModelId = input.requestedModelId;
  if (requestedModelId != null) {
    plan = ExecutionPlan(
      phases: plan.phases,
      boundAccountIds: plan.boundAccountIds,
      agents: [
        for (final agent in plan.agents)
          PlanAgent(
            role: agent.role,
            accountId: agent.accountId,
            modelId: requestedModelId,
          ),
      ],
    );
  }

  if (account.availability == Availability.quotaExhausted ||
      account.availability == Availability.restricted) {
    return PauseTeamDecision(
      code: 'quota',
      message: quotaMessage(account),
      alternatives: alternativesFor(account.id, input),
    );
  }

  final unproven =
      account.availability == Availability.unknown ||
      account.availability == Availability.notProbed;
  if (unproven && input.mode == OperationMode.restricted) {
    return BlockDecision(
      code: BlockCode.unprovenAvailability,
      message: account.availability == Availability.notProbed
          ? 'A disponibilidade ainda não foi verificada. O modo restrito não inicia a execução.'
          : 'O provedor não informou a quota restante. O modo restrito não inicia a execução.',
    );
  }

  if (plan.agents.isEmpty) {
    return const BlockDecision(
      code: BlockCode.noEconomyModel,
      message: 'Não há modelo utilizável nesta conta.',
    );
  }
  final leadModelId = plan.agents.first.modelId;
  ModelDefinition? leadModel;
  for (final model in input.models) {
    if (model.id == leadModelId) leadModel = model;
  }

  final approvalRequired = needsApproval(
    input,
    policy == PolicyDecision.allowWithApproval
        ? PolicyDecision.allowWithApproval
        : PolicyDecision.allow,
    plan,
    unproven,
  );
  final covered = plan.agents.every(
    (agent) => grantCovers(
      input.grants,
      input.executionId,
      agent.accountId,
      agent.modelId,
    ),
  );
  if (approvalRequired && !covered) {
    final billing = account.billingType == null
        ? 'conta'
        : account.billingType!.label.toLowerCase();
    final prompt =
        'Esta tarefa utilizará ${leadModel?.name ?? 'o modelo selecionado'} pela $billing conectada (${account.label}). Deseja autorizar esta execução?';
    return AwaitingAuthorization(
      plan: plan,
      prompt: prompt,
      accountId: account.id,
      modelId: leadModelId,
      billingLabel: account.billingType?.label ?? 'Conta sem tipo de cobrança',
      alternativeModels: [
        for (final model in usable)
          if (model.id != leadModelId)
            ModelOption(id: model.id, name: model.name, accountId: account.id),
      ],
    );
  }

  return ReadyDecision(
    plan: plan,
    message:
        'Plano autorizado na conta ${account.label}. Todas as fases usam essa mesma conta.',
  );
}

PauseTeamResult pauseTeam({
  required OperationMode mode,
  required String accountId,
  required String reason,
  required List<TeamExecution> executions,
  required List<IntegrationAccount> accounts,
  required List<ModelDefinition> models,
  required List<ScopePolicy> policies,
}) {
  IntegrationAccount? account;
  for (final item in accounts) {
    if (item.id == accountId) account = item;
  }
  final affectedTasks = <String>{
    for (final execution in executions)
      if (execution.accountId == accountId) execution.taskId,
  };
  final affected = executions
      .where((execution) => affectedTasks.contains(execution.taskId))
      .toList();
  final providerName = account?.provider.label ?? 'A integração';
  final message = reason == 'disconnected'
      ? '$providerName desconectou durante a execução. A equipe foi pausada e a sessão conhecida foi preservada.'
      : account != null && account.billingType == BillingType.providerCredits
      ? '$providerName atingiu o limite de créditos disponível. A equipe foi pausada.'
      : '$providerName atingiu o limite de utilização disponível. A equipe foi pausada.';

  return PauseTeamResult(
    message: message,
    executionIds: affected.map((execution) => execution.id).toList(),
    taskIds: affectedTasks.toList(),
    alternatives: account == null
        ? const []
        : alternativesFor(
            account.id,
            EvaluateInput(
              mode: mode,
              executionId: '',
              complexity: Complexity.standard,
              relevantOperation: false,
              destructive: false,
              consumptionPolicy: ApprovalMode.automatic,
              accounts: accounts,
              models: models,
              policies: policies,
              grants: const [],
            ),
          ),
  );
}

const _resumable = {
  ExecutionStatus.pausedByUser,
  ExecutionStatus.pausedByLimit,
  ExecutionStatus.awaitingAuthorization,
  ExecutionStatus.awaitingAvailability,
};

ResumeDecision decideResume({
  required ExecutionStatus status,
  required String? sessionId,
  required bool resumable,
}) {
  if (!_resumable.contains(status)) {
    return const RejectResume('Esta execução não está pausada.');
  }
  if (sessionId != null && resumable) return SameSessionResume(sessionId);
  return const NewExecutionResume(
    'Não é possível retomar a sessão original. Autorizar uma nova execução com o contexto recuperado?',
  );
}

List<ModelDefinition> defaultModels() => resolveCatalog(const {});
