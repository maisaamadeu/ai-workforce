enum OperationMode {
  economic,
  balanced,
  restricted;

  static OperationMode parse(String value) =>
      OperationMode.values.byName(value);
}

enum ProviderId {
  claudeCode('claude-code', 'claude', 'Claude Code'),
  codex('codex', 'codex', 'Codex'),
  cursor('cursor', 'agent', 'Cursor'),
  copilot('copilot', 'copilot', 'GitHub Copilot');

  const ProviderId(this.wire, this.binary, this.label);
  final String wire;
  final String binary;
  final String label;

  static ProviderId parse(String value) =>
      ProviderId.values.firstWhere((item) => item.wire == value);
}

enum BillingType {
  personalSubscription('personal-subscription', 'Assinatura pessoal'),
  corporateSubscription('corporate-subscription', 'Assinatura corporativa'),
  meteredApi('metered-api', 'API com cobrança por utilização'),
  providerCredits('provider-credits', 'Créditos do provedor'),
  unmetered('unmetered', 'Sem contabilização do provedor');

  const BillingType(this.wire, this.label);
  final String wire;
  final String label;

  static BillingType parse(String value) =>
      BillingType.values.firstWhere((item) => item.wire == value);
}

enum Availability {
  notProbed('not-probed', 'Não verificada'),
  disconnected('disconnected', 'Desconectada'),
  unauthenticated('unauthenticated', 'Sem autenticação'),
  available('available', 'Disponível'),
  unknown('unknown', 'Desconhecida'),
  quotaExhausted('quota-exhausted', 'Limite atingido'),
  restricted('restricted', 'Restrita');

  const Availability(this.wire, this.label);
  final String wire;
  final String label;

  static Availability parse(String value) =>
      Availability.values.firstWhere((item) => item.wire == value);
}

enum AuthState {
  authenticated,
  unauthenticated,
  disconnected;

  static AuthState parse(String value) => AuthState.values.byName(value);
}

enum ModelClass {
  economy('economy'),
  standard('standard'),
  reasoning('reasoning'),
  explicitPremium('explicit-premium');

  const ModelClass(this.wire);
  final String wire;

  static ModelClass parse(String value) =>
      ModelClass.values.firstWhere((item) => item.wire == value);
}

enum PolicyDecision {
  allow,
  allowWithApproval('allow-with-approval'),
  deny;

  const PolicyDecision([String? wire]) : wire = wire ?? '';
  final String wire;

  String get value => wire.isEmpty ? name : wire;

  static PolicyDecision parse(String value) =>
      PolicyDecision.values.firstWhere((item) => item.value == value);
}

enum PolicyScope { organization, workspace, project, agent, execution }

enum Complexity { simple, standard, architecture }

enum Phase { analyze, plan, implement, review }

enum AgentRole { executor, architect, developer, reviewer }

enum ExecutionStatus {
  awaitingAuthorization('awaiting-authorization'),
  awaitingAvailability('awaiting-availability'),
  pausedByUser('paused-by-user'),
  pausedByLimit('paused-by-limit'),
  cancelling,
  cancelled,
  blocked,
  ready,
  failed;

  const ExecutionStatus([String? wire]) : wire = wire ?? '';
  final String wire;
  String get value => wire.isEmpty ? name : wire;

  static ExecutionStatus parse(String value) =>
      ExecutionStatus.values.firstWhere((item) => item.value == value);
}

enum UsageUnit {
  appTokens('app-tokens', 'Tokens desta aplicação'),
  providerCredits('provider-credits', 'Créditos do provedor'),
  estimatedUsd('estimated-usd', 'Custo estimado'),
  providerQuota('provider-quota', 'Quota informada pelo provedor');

  const UsageUnit(this.wire, this.label);
  final String wire;
  final String label;

  static UsageUnit parse(String value) =>
      UsageUnit.values.firstWhere((item) => item.wire == value);
}

enum ApprovalCategory {
  consumption,
  skillInstall('skill-install'),
  mcp,
  adminCommand('admin-command'),
  configFile('config-file'),
  globalInstructions('global-instructions'),
  deleteFiles('delete-files'),
  migration,
  gitDestructive('git-destructive'),
  crossProject('cross-project'),
  extraResources('extra-resources');

  const ApprovalCategory([String? wire]) : wire = wire ?? '';
  final String wire;
  String get value => wire.isEmpty ? name : wire;

  static ApprovalCategory parse(String value) =>
      ApprovalCategory.values.firstWhere((item) => item.value == value);
}

enum ApprovalMode {
  automatic,
  requireApproval('require-approval'),
  forbidden;

  const ApprovalMode([String? wire]) : wire = wire ?? '';
  final String wire;
  String get value => wire.isEmpty ? name : wire;

  static ApprovalMode parse(String value) =>
      ApprovalMode.values.firstWhere((item) => item.value == value);
}

enum TaskStatus {
  open,
  blocked,
  paused,
  awaitingAuthorization('awaiting-authorization'),
  awaitingAvailability('awaiting-availability'),
  cancelled;

  const TaskStatus([String? wire]) : wire = wire ?? '';
  final String wire;
  String get value => wire.isEmpty ? name : wire;

  static TaskStatus parse(String value) =>
      TaskStatus.values.firstWhere((item) => item.value == value);
}

enum BlockCode {
  unauthenticated,
  disconnected,
  notAuthorized('not-authorized'),
  modelDenied('model-denied'),
  meteredBlocked('metered-blocked'),
  unprovenAvailability('unproven-availability'),
  premiumDisabled('premium-disabled'),
  noEconomyModel('no-economy-model'),
  forbidden,
  chooseAccount('choose-account');

  const BlockCode([String? wire]) : wire = wire ?? '';
  final String wire;
  String get value => wire.isEmpty ? name : wire;
}

const localOperator = 'local-operator';
const agentActor = 'agent';

const blockedMeteredEnv = [
  'ANTHROPIC_API_KEY',
  'OPENAI_API_KEY',
  'COPILOT_PROVIDER_API_KEY',
  'COPILOT_PROVIDER_BASE_URL',
  'COPILOT_PROVIDER_TYPE',
  'CURSOR_API_KEY',
];

const workforceEvents = (
  authorizationRequested: 'usage.authorization.requested',
  authorizationDecided: 'usage.authorization.decided',
  availabilityChanged: 'usage.availability.changed',
  quotaExhausted: 'usage.quota.exhausted',
  executionStateChanged: 'execution.state.changed',
  resumeRequested: 'execution.resume.requested',
  resumeRejected: 'execution.resume.rejected',
);

class ModelDefinition {
  const ModelDefinition({
    required this.id,
    required this.provider,
    required this.name,
    required this.modelClass,
    required this.enabled,
    required this.cliAlias,
  });

  final String id;
  final ProviderId provider;
  final String name;
  final ModelClass modelClass;
  final bool enabled;
  final String? cliAlias;

  ModelDefinition copyWith({bool? enabled}) => ModelDefinition(
    id: id,
    provider: provider,
    name: name,
    modelClass: modelClass,
    enabled: enabled ?? this.enabled,
    cliAlias: cliAlias,
  );
}

class IntegrationAccount {
  const IntegrationAccount({
    required this.id,
    required this.provider,
    required this.label,
    required this.billingType,
    required this.authState,
    required this.availability,
    required this.detectedApiKey,
    required this.meteredAuthorized,
    required this.configured,
    required this.authorizedModelIds,
    required this.cliInstalled,
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
  final List<String> authorizedModelIds;
  final bool cliInstalled;

  IntegrationAccount copyWith({
    AuthState? authState,
    Availability? availability,
    bool? detectedApiKey,
    List<String>? authorizedModelIds,
    bool? cliInstalled,
  }) {
    return IntegrationAccount(
      id: id,
      provider: provider,
      label: label,
      billingType: billingType,
      authState: authState ?? this.authState,
      availability: availability ?? this.availability,
      detectedApiKey: detectedApiKey ?? this.detectedApiKey,
      meteredAuthorized: meteredAuthorized,
      configured: configured,
      authorizedModelIds: authorizedModelIds ?? this.authorizedModelIds,
      cliInstalled: cliInstalled ?? this.cliInstalled,
    );
  }
}

class ScopePolicy {
  const ScopePolicy({
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

class ConsumptionGrant {
  const ConsumptionGrant({
    required this.executionId,
    required this.accountId,
    required this.modelId,
    required this.kind,
    required this.result,
    this.limitAmount,
    this.consumedAmount,
  });

  final String executionId;
  final String accountId;
  final String modelId;
  final String kind;
  final String result;
  final double? limitAmount;
  final double? consumedAmount;
}

class PlanAgent {
  const PlanAgent({
    required this.role,
    required this.accountId,
    required this.modelId,
  });

  final AgentRole role;
  final String accountId;
  final String modelId;

  Map<String, String> toJson() => {
    'role': role.name,
    'accountId': accountId,
    'modelId': modelId,
  };

  static PlanAgent fromJson(Map<String, Object?> json) => PlanAgent(
    role: AgentRole.values.byName(json['role']! as String),
    accountId: json['accountId']! as String,
    modelId: json['modelId']! as String,
  );
}

class ExecutionPlan {
  const ExecutionPlan({
    required this.phases,
    required this.agents,
    required this.boundAccountIds,
  });

  final List<Phase> phases;
  final List<PlanAgent> agents;
  final List<String> boundAccountIds;
  bool get sameAccount => true;

  Map<String, Object?> toJson() => {
    'phases': phases.map((phase) => phase.name).toList(),
    'agents': agents.map((agent) => agent.toJson()).toList(),
    'boundAccountIds': boundAccountIds,
    'sameAccount': true,
  };

  static ExecutionPlan fromJson(Map<String, Object?> json) => ExecutionPlan(
    phases: (json['phases']! as List)
        .map((item) => Phase.values.byName(item as String))
        .toList(),
    agents: (json['agents']! as List)
        .map(
          (item) => PlanAgent.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    boundAccountIds: (json['boundAccountIds']! as List).cast<String>(),
  );
}

class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    required this.accountId,
  });

  final String id;
  final String name;
  final String accountId;

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'accountId': accountId,
  };
}

sealed class StartDecision {
  const StartDecision();
  String get outcome;
  String get message;
}

final class ReadyDecision extends StartDecision {
  const ReadyDecision({required this.plan, required this.message});

  final ExecutionPlan plan;
  @override
  final String message;
  @override
  String get outcome => 'ready';
}

final class AwaitingAuthorization extends StartDecision {
  const AwaitingAuthorization({
    required this.plan,
    required this.prompt,
    required this.accountId,
    required this.modelId,
    required this.billingLabel,
    required this.alternativeModels,
  });

  final ExecutionPlan plan;
  final String prompt;
  final String accountId;
  final String modelId;
  final String billingLabel;
  final List<ModelOption> alternativeModels;

  @override
  String get outcome => 'awaiting-authorization';
  @override
  String get message => prompt;
}

final class BlockDecision extends StartDecision {
  const BlockDecision({required this.code, required this.message});

  final BlockCode code;
  @override
  final String message;
  @override
  String get outcome => 'block';
}

final class PauseTeamDecision extends StartDecision {
  const PauseTeamDecision({
    required this.code,
    required this.message,
    required this.alternatives,
  });

  final String code;
  @override
  final String message;
  final List<ModelOption> alternatives;
  bool get preserveSession => true;
  @override
  String get outcome => 'pause-team';
}

class ObservedUsage {
  const ObservedUsage({
    required this.unit,
    required this.amount,
    required this.source,
  });

  final UsageUnit unit;
  final double? amount;
  final String source;
}

List<ObservedUsage> emptyUsage() => const [
  ObservedUsage(unit: UsageUnit.appTokens, amount: null, source: 'app'),
  ObservedUsage(
    unit: UsageUnit.providerCredits,
    amount: null,
    source: 'provider',
  ),
  ObservedUsage(unit: UsageUnit.estimatedUsd, amount: null, source: 'estimate'),
  ObservedUsage(
    unit: UsageUnit.providerQuota,
    amount: null,
    source: 'provider',
  ),
];

class TeamExecution {
  const TeamExecution({
    required this.id,
    required this.taskId,
    required this.accountId,
    required this.status,
    required this.sessionId,
  });

  final String id;
  final String taskId;
  final String accountId;
  final ExecutionStatus status;
  final String? sessionId;
}

class PauseTeamResult {
  const PauseTeamResult({
    required this.message,
    required this.executionIds,
    required this.taskIds,
    required this.alternatives,
  });

  final String message;
  final List<String> executionIds;
  final List<String> taskIds;
  final List<ModelOption> alternatives;
  bool get preserveSession => true;
  String get outcome => 'pause-team';
}

sealed class ResumeDecision {
  const ResumeDecision();
}

final class SameSessionResume extends ResumeDecision {
  const SameSessionResume(this.sessionId);
  final String sessionId;
  String get outcome => 'same-session';
  String get label => 'retomada';
}

final class NewExecutionResume extends ResumeDecision {
  const NewExecutionResume(this.message);
  final String message;
  String get outcome => 'new-execution';
  String get label => 'nova execução';
}

final class RejectResume extends ResumeDecision {
  const RejectResume(this.message);
  final String message;
  String get outcome => 'reject';
}

const modeCopy = {
  OperationMode.economic: 'Usa modelos econômicos, evita delegação e pede aprovação para operações relevantes.',
  OperationMode.balanced: 'Permite equipe quando a complexidade justifica, dentro dos limites da tarefa e do workspace.',
  OperationMode.restricted: 'Só modelos e contas já autorizados. Disponibilidade desconhecida bloqueia a partida.',
};
