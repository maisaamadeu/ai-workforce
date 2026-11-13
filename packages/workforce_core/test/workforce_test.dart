import 'dart:io';

import 'package:test/test.dart';
import 'package:workforce_core/workforce_core.dart';

void main() {
  test('uma conta autorizada chega até a espera do adaptador sem registrar consumo', () {
    final workforce = LocalWorkforce.open(path: ':memory:');
    addTearDown(workforce.close);
    final directory = Directory.systemTemp.createTempSync(
      'ai-workforce-project',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    workforce.setMode(localOperator, OperationMode.economic);
    final workspace = workforce.createWorkspace(localOperator, 'STI 3');
    workforce.recordProviderFact(
      'acc-claude',
      Availability.available,
      AuthState.authenticated,
    );
    workforce.savePolicy(
      localOperator,
      workspace.id,
      'acc-claude',
      decision: PolicyDecision.allow,
      billingType: BillingType.corporateSubscription,
      label: 'Claude corporativo',
      authorizedModelIds: const [
        'claude-haiku',
        'claude-sonnet',
        'claude-opus',
      ],
      meteredAuthorized: false,
    );
    final project = workforce.createProject(
      localOperator,
      workspace.id,
      'Núcleo',
      directory.path,
    );
    final view = workforce.createTask(
      localOperator,
      project.id,
      title: 'Mapear o módulo',
      complexity: Complexity.simple,
    );

    expect(view.task.status, TaskStatus.awaitingAvailability);
    expect(
      view.executions.single.execution.status,
      ExecutionStatus.awaitingAvailability,
    );
    expect(view.executions.single.plan?.agents.single.modelId, 'claude-haiku');
    expect(
      view.executions.single.execution.interruptionReason,
      contains('Nenhuma chamada foi feita'),
    );
    final usage = workforce
        .snapshot()
        .integrations
        .firstWhere((item) => item.account.id == 'acc-claude')
        .usage;
    expect(usage.every((meter) => meter.amount == null), isTrue);
  });

  test(
    'disponibilidade não verificada no modo restrito bloqueia a partida',
    () {
      final workforce = LocalWorkforce.open(path: ':memory:');
      addTearDown(workforce.close);
      final directory = Directory.systemTemp.createTempSync(
        'ai-workforce-restricted',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      workforce.setMode(localOperator, OperationMode.restricted);
      final workspace = workforce.createWorkspace(localOperator, 'Restrito');
      workforce.savePolicy(
        localOperator,
        workspace.id,
        'acc-claude',
        decision: PolicyDecision.allow,
        billingType: BillingType.corporateSubscription,
        label: 'Claude',
        authorizedModelIds: const ['claude-haiku'],
        meteredAuthorized: false,
      );
      final project = workforce.createProject(
        localOperator,
        workspace.id,
        'Projeto',
        directory.path,
      );
      final view = workforce.createTask(
        localOperator,
        project.id,
        title: 'Não iniciar',
        complexity: Complexity.simple,
      );
      expect(view.task.status, TaskStatus.blocked);
      expect(
        view.executions.single.execution.interruptionReason,
        contains('não foi verificada'),
      );
    },
  );

  test('um agente não altera o modo', () {
    final workforce = LocalWorkforce.open(path: ':memory:');
    addTearDown(workforce.close);
    expect(
      () => workforce.setMode(agentActor, OperationMode.balanced),
      throwsA(
        isA<WorkforceException>().having(
          (error) => error.code,
          'code',
          'agent-forbidden',
        ),
      ),
    );
  });

  test('o cofre em memória não vaza para outro nome', () async {
    final store = MemoryCredentialStore();
    await store.write('claude', 'segredo');
    expect(await store.read('claude'), 'segredo');
    expect(await store.read('codex'), isNull);
    await store.delete('claude');
    expect(await store.read('claude'), isNull);
  });
}
