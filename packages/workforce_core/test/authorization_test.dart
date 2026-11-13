import 'package:test/test.dart';
import 'package:workforce_core/workforce_core.dart';

IntegrationAccount account(
  ProviderId provider,
  String id, {
  List<String> models = const [],
}) {
  return IntegrationAccount(
    id: id,
    provider: provider,
    label: id,
    billingType: BillingType.corporateSubscription,
    authState: AuthState.authenticated,
    availability: Availability.available,
    detectedApiKey: false,
    meteredAuthorized: false,
    configured: true,
    authorizedModelIds: models,
    cliInstalled: true,
  );
}

final claude = IntegrationAccount(
  id: 'claude',
  provider: ProviderId.claudeCode,
  label: 'Claude corporativo',
  billingType: BillingType.corporateSubscription,
  authState: AuthState.authenticated,
  availability: Availability.available,
  detectedApiKey: false,
  meteredAuthorized: false,
  configured: true,
  authorizedModelIds: const ['claude-haiku', 'claude-sonnet', 'claude-opus'],
  cliInstalled: true,
);

ScopePolicy allow(
  String accountId, [
  PolicyDecision decision = PolicyDecision.allow,
]) {
  return ScopePolicy(
    scope: PolicyScope.workspace,
    scopeId: 'sti3',
    accountId: accountId,
    decision: decision,
  );
}

EvaluateInput base({
  OperationMode mode = OperationMode.economic,
  String executionId = 'exec-1',
  Complexity complexity = Complexity.simple,
  bool relevantOperation = false,
  bool destructive = false,
  ApprovalMode consumptionPolicy = ApprovalMode.automatic,
  List<IntegrationAccount>? accounts,
  List<ModelDefinition>? models,
  List<ScopePolicy>? policies,
  List<ConsumptionGrant> grants = const [],
  String? requestedAccountId,
  String? requestedModelId,
  int? agentLimit,
}) {
  return EvaluateInput(
    mode: mode,
    executionId: executionId,
    complexity: complexity,
    relevantOperation: relevantOperation,
    destructive: destructive,
    consumptionPolicy: consumptionPolicy,
    accounts: accounts ?? [claude],
    models: models ?? defaultModels(),
    policies: policies ?? [allow('claude')],
    grants: grants,
    requestedAccountId: requestedAccountId,
    requestedModelId: requestedModelId,
    agentLimit: agentLimit,
  );
}

void main() {
  group('cenários de aceite', () {
    test('executa o ciclo na assinatura corporativa autorizada', () {
      final decision = evaluateStart(base());
      expect(decision, isA<ReadyDecision>());
      final ready = decision as ReadyDecision;
      expect(ready.plan.phases, [
        Phase.analyze,
        Phase.plan,
        Phase.implement,
        Phase.review,
      ]);
      expect(ready.plan.agents.single.role, AgentRole.executor);
      expect(ready.plan.agents.single.modelId, 'claude-haiku');
      expect(ready.plan.sameAccount, isTrue);
      expect(ready.plan.agents.map((agent) => agent.accountId).toSet(), {
        'claude',
      });
    });

    test('bloqueia Claude sem autenticação', () {
      final decision = evaluateStart(
        base(accounts: [claude.copyWith(authState: AuthState.unauthenticated)]),
      );
      expect(decision, isA<BlockDecision>());
      expect((decision as BlockDecision).code, BlockCode.unauthenticated);
    });

    test('pausa a equipe quando a quota acaba e não oferece API paga', () {
      final metered = account(
        ProviderId.claudeCode,
        'claude-api',
        models: ['claude-haiku'],
      ).copyWith();
      final api = IntegrationAccount(
        id: 'claude-api',
        provider: ProviderId.claudeCode,
        label: 'claude-api',
        billingType: BillingType.meteredApi,
        authState: AuthState.authenticated,
        availability: Availability.available,
        detectedApiKey: true,
        meteredAuthorized: false,
        configured: true,
        authorizedModelIds: const ['claude-haiku'],
        cliInstalled: true,
      );
      final decision = evaluateStart(
        base(
          accounts: [
            claude.copyWith(availability: Availability.quotaExhausted),
            api,
          ],
          policies: [allow('claude'), allow('claude-api')],
        ),
      );
      expect(decision, isA<PauseTeamDecision>());
      final paused = decision as PauseTeamDecision;
      expect(paused.alternatives, isEmpty);
      expect(paused.preserveSession, isTrue);
      expect(metered.id, 'claude-api');
    });

    test('pede autorização quando a disponibilidade é desconhecida', () {
      final decision = evaluateStart(
        base(accounts: [claude.copyWith(availability: Availability.unknown)]),
      );
      expect(decision, isA<AwaitingAuthorization>());
    });

    test('trata integração ainda não verificada como disponibilidade não comprovada', () {
      final decision = evaluateStart(
        base(
          mode: OperationMode.restricted,
          accounts: [
            claude.copyWith(
              authState: AuthState.disconnected,
              availability: Availability.notProbed,
            ),
          ],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.unprovenAvailability);
    });

    test('bloqueia disponibilidade desconhecida no modo restrito', () {
      final decision = evaluateStart(
        base(
          mode: OperationMode.restricted,
          accounts: [claude.copyWith(availability: Availability.unknown)],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.unprovenAvailability);
    });

    test('mantém a API key detectada bloqueada', () {
      final api = IntegrationAccount(
        id: 'claude-api',
        provider: ProviderId.claudeCode,
        label: 'Claude API',
        billingType: BillingType.meteredApi,
        authState: AuthState.authenticated,
        availability: Availability.available,
        detectedApiKey: true,
        meteredAuthorized: false,
        configured: true,
        authorizedModelIds: const ['claude-haiku'],
        cliInstalled: true,
      );
      final decision = evaluateStart(
        base(
          requestedAccountId: 'claude-api',
          accounts: [claude, api],
          policies: [allow('claude'), allow('claude-api')],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.meteredBlocked);
    });

    test('não trata a API key detectada como substituta da assinatura', () {
      final decision = evaluateStart(
        base(accounts: [claude.copyWith(detectedApiKey: true)]),
      );
      expect(decision, isA<ReadyDecision>());
    });

    test('bloqueia modelo fora da lista do workspace', () {
      final decision = evaluateStart(
        base(
          mode: OperationMode.balanced,
          requestedModelId: 'claude-opus',
          accounts: [
            claude.copyWith(authorizedModelIds: ['claude-haiku']),
          ],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.modelDenied);
    });

    test('pausa o Copilot quando os créditos acabam', () {
      final copilot = IntegrationAccount(
        id: 'copilot',
        provider: ProviderId.copilot,
        label: 'Copilot pessoal',
        billingType: BillingType.providerCredits,
        authState: AuthState.authenticated,
        availability: Availability.quotaExhausted,
        detectedApiKey: false,
        meteredAuthorized: false,
        configured: true,
        authorizedModelIds: const ['copilot-economy'],
        cliInstalled: true,
      );
      final decision = evaluateStart(
        base(
          accounts: [copilot],
          policies: [allow('copilot', PolicyDecision.allowWithApproval)],
        ),
      );
      expect(decision, isA<PauseTeamDecision>());
      expect(decision.message, contains('créditos'));
    });

    test(
      'pausa a equipe inteira e preserva a sessão quando a integração cai',
      () {
        final result = pauseTeam(
          mode: OperationMode.economic,
          accountId: 'claude',
          reason: 'disconnected',
          executions: const [
            TeamExecution(
              id: 'a',
              taskId: 'task',
              accountId: 'claude',
              status: ExecutionStatus.ready,
              sessionId: 'sess-1',
            ),
            TeamExecution(
              id: 'b',
              taskId: 'task',
              accountId: 'claude',
              status: ExecutionStatus.awaitingAvailability,
              sessionId: null,
            ),
          ],
          accounts: [claude],
          models: defaultModels(),
          policies: [allow('claude')],
        );
        expect(result.executionIds, ['a', 'b']);
        expect(result.preserveSession, isTrue);
        expect(result.message, contains('desconectou'));
      },
    );

    test(
      'retoma a mesma sessão e recusa chamar uma execução nova de retomada',
      () {
        final same = decideResume(
          status: ExecutionStatus.pausedByLimit,
          sessionId: 'sess-1',
          resumable: true,
        );
        expect(same, isA<SameSessionResume>());
        expect((same as SameSessionResume).label, 'retomada');
        final fresh = decideResume(
          status: ExecutionStatus.pausedByLimit,
          sessionId: null,
          resumable: false,
        );
        expect(fresh, isA<NewExecutionResume>());
        expect((fresh as NewExecutionResume).label, 'nova execução');
      },
    );

    test('não faz fallback para provedor negado no workspace', () {
      final codex = IntegrationAccount(
        id: 'codex',
        provider: ProviderId.codex,
        label: 'codex',
        billingType: BillingType.personalSubscription,
        authState: AuthState.authenticated,
        availability: Availability.available,
        detectedApiKey: false,
        meteredAuthorized: false,
        configured: true,
        authorizedModelIds: const ['codex-economy'],
        cliInstalled: true,
      );
      final decision = evaluateStart(
        base(
          accounts: [
            claude.copyWith(availability: Availability.quotaExhausted),
            codex,
          ],
          policies: [allow('claude'), allow('codex', PolicyDecision.deny)],
        ),
      );
      expect((decision as PauseTeamDecision).alternatives, isEmpty);
    });
  });

  group('modos e uma assinatura', () {
    test('no modo econômico pede aprovação para arquitetura e segue com um agente econômico', () {
      final waiting = evaluateStart(base(complexity: Complexity.architecture));
      expect(waiting, isA<AwaitingAuthorization>());
      final pending = waiting as AwaitingAuthorization;
      expect(pending.modelId, 'claude-haiku');
      expect(
        pending.alternativeModels.map((model) => model.id),
        isNot(contains('claude-opus')),
      );

      final ready = evaluateStart(
        base(
          complexity: Complexity.architecture,
          grants: const [
            ConsumptionGrant(
              executionId: 'exec-1',
              accountId: 'claude',
              modelId: 'claude-haiku',
              kind: 'once',
              result: 'approved',
            ),
          ],
        ),
      );
      expect((ready as ReadyDecision).plan.agents, hasLength(1));
    });

    test('não reaproveita autorização de outra execução', () {
      final decision = evaluateStart(
        base(
          executionId: 'exec-2',
          complexity: Complexity.architecture,
          grants: const [
            ConsumptionGrant(
              executionId: 'exec-1',
              accountId: 'claude',
              modelId: 'claude-haiku',
              kind: 'once',
              result: 'approved',
            ),
          ],
        ),
      );
      expect(decision, isA<AwaitingAuthorization>());
    });

    test('no modo equilibrado monta a equipe dentro da mesma conta', () {
      final decision = evaluateStart(
        base(
          mode: OperationMode.balanced,
          complexity: Complexity.architecture,
          agentLimit: 4,
        ),
      );
      final ready = decision as ReadyDecision;
      expect(ready.plan.agents.map((agent) => agent.role), [
        AgentRole.architect,
        AgentRole.developer,
        AgentRole.reviewer,
      ]);
      expect(
        ready.plan.agents.every((agent) => agent.accountId == 'claude'),
        isTrue,
      );
      expect(ready.plan.agents.map((agent) => agent.modelId), [
        'claude-opus',
        'claude-sonnet',
        'claude-haiku',
      ]);
    });

    test('respeita o limite de agentes do workspace', () {
      final decision = evaluateStart(
        base(
          mode: OperationMode.balanced,
          complexity: Complexity.architecture,
          agentLimit: 1,
        ),
      );
      expect((decision as ReadyDecision).plan.agents, hasLength(1));
    });

    test('uma tarefa simples usa um agente mesmo no modo equilibrado', () {
      final decision = evaluateStart(
        base(mode: OperationMode.balanced, complexity: Complexity.simple),
      );
      final ready = decision as ReadyDecision;
      expect(ready.plan.agents, hasLength(1));
      expect(ready.plan.agents.single.modelId, 'claude-haiku');
    });

    test('não eleva o modo econômico para um modelo intermediário', () {
      final decision = evaluateStart(
        base(
          accounts: [
            claude.copyWith(authorizedModelIds: ['claude-sonnet']),
          ],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.noEconomyModel);
    });

    test('negação do workspace impede a permissão da organização', () {
      final decision = evaluateStart(
        base(
          policies: [
            const ScopePolicy(
              scope: PolicyScope.organization,
              scopeId: 'org',
              accountId: 'claude',
              decision: PolicyDecision.allow,
            ),
            allow('claude', PolicyDecision.deny),
          ],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.notAuthorized);
    });

    test('uma permissão ampla não afrouxa a exigência de aprovação', () {
      final decision = evaluateStart(
        base(
          policies: [
            const ScopePolicy(
              scope: PolicyScope.organization,
              scopeId: 'org',
              accountId: 'claude',
              decision: PolicyDecision.allowWithApproval,
            ),
            allow('claude'),
          ],
        ),
      );
      expect(decision, isA<AwaitingAuthorization>());
    });

    test('conta conectada sem política não autoriza consumo', () {
      final decision = evaluateStart(base(policies: const []));
      expect((decision as BlockDecision).code, BlockCode.notAuthorized);
    });

    test('mantém Fable desabilitado', () {
      final decision = evaluateStart(
        base(
          mode: OperationMode.balanced,
          requestedModelId: 'claude-fable',
          accounts: [
            claude.copyWith(
              authorizedModelIds: [
                ...claude.authorizedModelIds,
                'claude-fable',
              ],
            ),
          ],
        ),
      );
      expect((decision as BlockDecision).code, BlockCode.premiumDisabled);
    });

    test(
      'usa Fable só depois de habilitação explícita e fora do modo econômico',
      () {
        final enabled = resolveCatalog({'claude-fable': true});
        final economic = evaluateStart(
          base(
            models: enabled,
            requestedModelId: 'claude-fable',
            accounts: [
              claude.copyWith(
                authorizedModelIds: ['claude-fable', 'claude-haiku'],
              ),
            ],
          ),
        );
        expect((economic as BlockDecision).code, BlockCode.modelDenied);

        final balanced = evaluateStart(
          base(
            mode: OperationMode.balanced,
            models: enabled,
            requestedModelId: 'claude-fable',
            accounts: [
              claude.copyWith(authorizedModelIds: ['claude-fable']),
            ],
            grants: const [
              ConsumptionGrant(
                executionId: 'exec-1',
                accountId: 'claude',
                modelId: 'claude-fable',
                kind: 'once',
                result: 'approved',
              ),
            ],
          ),
        );
        expect(balanced, isA<ReadyDecision>());
      },
    );
  });

  group('proteção de credenciais e operador', () {
    test('remove variáveis de cobrança medida do ambiente do processo', () {
      final clean = sanitizeEnv({
        'PATH': '/usr/bin',
        'ANTHROPIC_API_KEY': 'sk-secret',
        'OPENAI_API_KEY': 'sk-secret',
        'COPILOT_PROVIDER_API_KEY': 'sk-secret',
      }, allowMetered: false);
      expect(clean['PATH'], '/usr/bin');
      for (final key in blockedMeteredEnv) {
        expect(clean.containsKey(key), isFalse);
      }
      expect(clean.toString(), isNot(contains('sk-secret')));
    });

    test('detecta presença de chave sem devolver o valor', () {
      final detected = detectMeteredEnv({
        'ANTHROPIC_API_KEY': 'sk-secret',
        'PATH': '/usr/bin',
      });
      expect(detected[ProviderId.claudeCode], isTrue);
      expect(detected[ProviderId.codex], isFalse);
      expect(detected.toString(), isNot(contains('sk-secret')));
    });

    test('impede um agente de autorizar ou alterar política', () {
      expect(
        () => assertLocalOperator(agentActor),
        throwsA(isA<OperatorError>()),
      );
      expect(() => assertLocalOperator(localOperator), returnsNormally);
    });
  });

  group('catálogo', () {
    test('não afirma disponibilidade de modelos concretos sem probe', () {
      final unbound = modelCatalog.where(
        (model) => model.provider != ProviderId.claudeCode,
      );
      expect(unbound.every((model) => model.cliAlias == null), isTrue);
      expect(
        modelCatalog.firstWhere((model) => model.id == 'claude-fable').enabled,
        isFalse,
      );
    });
  });
}
