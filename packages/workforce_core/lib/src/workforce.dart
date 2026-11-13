import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'authorization.dart';
import 'catalog.dart';
import 'contracts.dart';
import 'database.dart';
import 'env.dart';
import 'ports.dart';
import 'probe.dart';
import 'repository.dart';

class WorkforceException implements Exception {
  WorkforceException(this.message, {this.code = 'bad-request'});
  final String message;
  final String code;

  @override
  String toString() => message;
}

class WorkforceEvent {
  const WorkforceEvent({
    required this.type,
    required this.payload,
    required this.at,
  });
  final String type;
  final Map<String, Object?> payload;
  final String at;
}

class IntegrationView {
  const IntegrationView({
    required this.account,
    required this.usage,
    required this.availabilityLabel,
    required this.cliInstalled,
    required this.detectedApiKey,
  });

  final AccountRow account;
  final List<ObservedUsage> usage;
  final String availabilityLabel;
  final bool cliInstalled;
  final bool detectedApiKey;
}

class Snapshot {
  const Snapshot({
    required this.organization,
    required this.workspaces,
    required this.integrations,
    required this.models,
    required this.tasks,
    required this.approvals,
    required this.approvalPolicies,
    required this.audit,
    required this.schemaVersion,
    required this.dataDirectory,
  });

  final OrganizationRow organization;
  final List<WorkspaceRow> workspaces;
  final List<IntegrationView> integrations;
  final List<ModelDefinition> models;
  final List<TaskRow> tasks;
  final List<ApprovalRow> approvals;
  final List<({ApprovalCategory category, ApprovalMode mode})> approvalPolicies;
  final List<AuditRow> audit;
  final int schemaVersion;
  final String dataDirectory;
}

class AccountPolicyView {
  const AccountPolicyView({
    required this.accountId,
    required this.provider,
    required this.label,
    required this.billingType,
    required this.decision,
    required this.authorizedModelIds,
    required this.meteredAuthorized,
    required this.configured,
  });

  final String accountId;
  final ProviderId provider;
  final String label;
  final BillingType? billingType;
  final PolicyDecision? decision;
  final List<String> authorizedModelIds;
  final bool meteredAuthorized;
  final bool configured;
}

class WorkspaceView {
  const WorkspaceView({
    required this.workspace,
    required this.projects,
    required this.tasks,
    required this.policies,
    required this.budget,
  });

  final WorkspaceRow workspace;
  final List<ProjectRow> projects;
  final List<TaskRow> tasks;
  final List<AccountPolicyView> policies;
  final ({String unit, double limitAmount})? budget;
}

class ProjectView {
  const ProjectView({required this.project, required this.tasks});
  final ProjectRow project;
  final List<TaskRow> tasks;
}

class ExecutionView {
  const ExecutionView({
    required this.execution,
    required this.plan,
    required this.events,
    required this.approval,
  });

  final ExecutionRow execution;
  final ExecutionPlan? plan;
  final List<
    ({String id, String type, Map<String, Object?> payload, String at})
  >
  events;
  final ApprovalRow? approval;
}

class TaskView {
  const TaskView({required this.task, required this.executions});
  final TaskRow task;
  final List<ExecutionView> executions;
}

class ResumeResult {
  const ResumeResult({
    required this.task,
    required this.outcome,
    required this.applied,
    required this.label,
    required this.message,
  });
  final TaskView task;
  final String outcome;
  final bool applied;
  final String label;
  final String message;
}

class LocalWorkforce {
  LocalWorkforce._(this._db, this._repo, this.dataDirectoryPath);
  final Database _db;
  final Repository _repo;
  final String dataDirectoryPath;
  final StreamController<WorkforceEvent> _events =
      StreamController<WorkforceEvent>.broadcast();

  factory LocalWorkforce.open({String? path}) {
    final directory = path == ':memory:'
        ? ''
        : (path == null ? dataDirectory() : File(path).parent.path);
    if (path != ':memory:' && path == null) {
      Directory(dataDirectory()).createSync(recursive: true);
    }
    final db = openDatabase(path ?? dataFile());
    return LocalWorkforce._(db, Repository(db), directory);
  }

  Stream<WorkforceEvent> get events => _events.stream;
  int get schemaVersionNumber => schemaVersion;

  void close() {
    _events.close();
    _db.dispose();
  }

  Snapshot snapshot() {
    final installed = probeInstalledClis();
    final detected = detectMeteredEnv(Platform.environment);
    return Snapshot(
      organization: _repo.organization(),
      workspaces: _repo.listWorkspaces(),
      integrations: [
        for (final account in _repo.accounts())
          IntegrationView(
            account: account,
            usage: emptyUsage(),
            availabilityLabel: account.availability.label,
            cliInstalled: installed[account.provider] ?? false,
            detectedApiKey:
                account.detectedApiKey || (detected[account.provider] ?? false),
          ),
      ],
      models: resolveCatalog(_repo.overrides()),
      tasks: _repo.recentTasks(),
      approvals: _repo.pendingApprovals(),
      approvalPolicies: _repo.approvalPolicies(),
      audit: _repo.recentAudit(),
      schemaVersion: schemaVersion,
      dataDirectory: dataDirectoryPath,
    );
  }

  OrganizationRow setMode(String? actor, OperationMode mode) {
    _requireOperator(actor);
    _repo.setMode(mode);
    _audit(
      actor,
      action: 'organization.mode',
      result: 'updated',
      detail: 'Modo global definido como ${mode.name}.',
    );
    return _repo.organization();
  }

  WorkspaceRow createWorkspace(String? actor, String name) {
    _requireOperator(actor);
    final trimmed = name.trim();
    if (trimmed.isEmpty)
      throw WorkforceException('Informe o nome do workspace.');
    final workspace = _repo.insertWorkspace(trimmed);
    _audit(
      actor,
      action: 'workspace.create',
      result: 'created',
      detail: 'Workspace ${workspace.name} criado.',
    );
    return workspace;
  }

  WorkspaceView workspaceView(String id) {
    final workspace = _repo.workspace(id);
    if (workspace == null)
      throw WorkforceException('Workspace não encontrado.', code: 'not-found');
    final policies = _repo.policiesFor([id]);
    return WorkspaceView(
      workspace: workspace,
      projects: _repo.listProjects(id),
      tasks: _repo.tasksByWorkspace(id),
      policies: [
        for (final account in _repo.accounts())
          AccountPolicyView(
            accountId: account.id,
            provider: account.provider,
            label: account.label,
            billingType: account.billingType,
            decision: _decisionOf(policies, account.id),
            authorizedModelIds: _repo.modelIds('workspace', id, account.id),
            meteredAuthorized: account.meteredAuthorized,
            configured: account.configured,
          ),
      ],
      budget: _repo.budget(id),
    );
  }

  WorkspaceView savePolicy(
    String? actor,
    String workspaceId,
    String accountId, {
    required PolicyDecision decision,
    required BillingType? billingType,
    required String label,
    required List<String> authorizedModelIds,
    required bool meteredAuthorized,
  }) {
    _requireOperator(actor);
    final workspace = _repo.workspace(workspaceId);
    if (workspace == null)
      throw WorkforceException('Workspace não encontrado.', code: 'not-found');
    final account = _repo.account(accountId);
    if (account == null)
      throw WorkforceException('Integração não encontrada.', code: 'not-found');
    final catalog = resolveCatalog(_repo.overrides());
    final unknown = authorizedModelIds.where(
      (modelId) => !catalog.any(
        (model) => model.id == modelId && model.provider == account.provider,
      ),
    );
    if (unknown.isNotEmpty)
      throw WorkforceException(
        'Há modelos que não pertencem a esta integração.',
      );
    _repo.transaction(() {
      _repo.updateAccount(
        id: accountId,
        label: label.trim().isEmpty ? account.label : label.trim(),
        billingType: billingType,
        meteredAuthorized: meteredAuthorized,
      );
      _repo.upsertPolicy(
        PolicyScope.workspace,
        workspaceId,
        accountId,
        decision,
      );
      _repo.replaceModelGrants(
        'workspace',
        workspaceId,
        accountId,
        authorizedModelIds,
      );
      _audit(
        actor,
        action: 'policy.save',
        provider: account.provider.wire,
        accountId: accountId,
        result: decision.value,
        limitApproved: meteredAuthorized
            ? 'cobrança medida autorizada'
            : 'cobrança medida bloqueada',
        detail:
            'Política do workspace ${workspace.name} para ${account.provider.label}.',
      );
    });
    return workspaceView(workspaceId);
  }

  ({String unit, double limitAmount})? setBudget(
    String? actor,
    String workspaceId,
    double? limitAmount,
  ) {
    _requireOperator(actor);
    if (_repo.workspace(workspaceId) == null)
      throw WorkforceException('Workspace não encontrado.', code: 'not-found');
    if (limitAmount == null) {
      _repo.clearBudget(workspaceId);
    } else if (!limitAmount.isFinite || limitAmount <= 0) {
      throw WorkforceException('O teto precisa ser um número maior que zero.');
    } else {
      _repo.setBudget(workspaceId, limitAmount);
    }
    _audit(
      actor,
      action: 'budget.set',
      result: limitAmount == null ? 'cleared' : 'updated',
      limitApproved: limitAmount?.toString(),
      detail: 'Teto de tokens observados nesta aplicação.',
    );
    return _repo.budget(workspaceId);
  }

  ProjectRow createProject(
    String? actor,
    String workspaceId,
    String name,
    String projectPath,
  ) {
    _requireOperator(actor);
    if (_repo.workspace(workspaceId) == null)
      throw WorkforceException('Workspace não encontrado.', code: 'not-found');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw WorkforceException('Informe o nome do projeto.');
    final resolved = _resolveProjectPath(projectPath);
    final project = _repo.insertProject(workspaceId, trimmed, resolved);
    _audit(
      actor,
      action: 'project.create',
      result: 'created',
      detail:
          'Projeto ${project.name} registrado em ${project.path}. O código não foi analisado.',
    );
    return project;
  }

  ProjectView projectView(String id) {
    final project = _repo.project(id);
    if (project == null)
      throw WorkforceException('Projeto não encontrado.', code: 'not-found');
    final tasks = _repo
        .tasksByWorkspace(project.workspaceId)
        .where((task) => task.projectId == id)
        .toList();
    return ProjectView(project: project, tasks: tasks);
  }

  TaskView createTask(
    String? actor,
    String projectId, {
    required String title,
    required Complexity complexity,
    bool relevantOperation = false,
    bool destructive = false,
    String? accountId,
    String? modelId,
  }) {
    _requireOperator(actor);
    final project = _repo.project(projectId);
    if (project == null)
      throw WorkforceException('Projeto não encontrado.', code: 'not-found');
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw WorkforceException('Informe a tarefa.');
    final workspace = _repo.workspace(project.workspaceId);
    if (workspace == null)
      throw WorkforceException('Workspace não encontrado.', code: 'not-found');
    final budget = _repo.budget(project.workspaceId);
    final mode = _repo.organization().mode;
    if (budget != null && mode == OperationMode.restricted) {
      throw WorkforceException(
        'Há um teto configurado e nenhuma estimativa do provedor. O modo restrito não inicia consumo desconhecido.',
        code: 'unproven-availability',
      );
    }
    final task = _repo.transaction(() {
      final created = _repo.insertTask(
        TaskRow(
          id: '',
          workspaceId: project.workspaceId,
          projectId: project.id,
          title: trimmed,
          complexity: complexity,
          relevant: relevantOperation || budget != null,
          destructive: destructive,
          status: TaskStatus.open,
          createdAt: '',
        ),
      );
      final execution = _repo.insertExecution(
        taskId: created.id,
        accountId: accountId,
        modelId: modelId,
        status: ExecutionStatus.ready,
        planJson: null,
        interruptionReason: null,
      );
      final decision = evaluateStart(
        _evaluationInput(
          project.workspaceId,
          project.id,
          execution.id,
          created,
          accountId,
          modelId,
        ),
      );
      _persistDecision(
        taskId: created.id,
        executionId: execution.id,
        decision: decision,
        actor: actor ?? localOperator,
      );
      return created;
    });
    return taskView(task.id);
  }

  TaskView taskView(String id) {
    final task = _repo.task(id);
    if (task == null)
      throw WorkforceException('Tarefa não encontrada.', code: 'not-found');
    final executions = [
      for (final execution in _repo.executionsForTask(id))
        ExecutionView(
          execution: execution,
          plan: execution.planJson == null
              ? null
              : ExecutionPlan.fromJson(
                  (jsonDecode(execution.planJson!) as Map)
                      .cast<String, Object?>(),
                ),
          events: _repo.events(execution.id),
          approval: _repo.pendingApprovalForExecution(execution.id),
        ),
    ];
    return TaskView(task: task, executions: executions);
  }

  TaskView decideApproval(
    String? actor,
    String approvalId, {
    required String action,
    String? modelId,
    double? limitAmount,
  }) {
    _requireOperator(actor);
    final approval = _repo.approval(approvalId);
    if (approval == null || approval.status != 'pending') {
      throw WorkforceException(
        'Autorização não encontrada.',
        code: 'not-found',
      );
    }
    final task = _repo.task(approval.taskId);
    final execution = _repo.execution(approval.executionId);
    if (task == null || execution == null)
      throw WorkforceException('Execução não encontrada.', code: 'not-found');

    if (action == 'deny') {
      _repo.decideApproval(approval.id, 'deny', null, 'denied');
      _repo.updateExecution(
        execution.id,
        execution.copyWith(
          status: ExecutionStatus.cancelled,
          interruptionReason: 'Autorização negada pelo operador.',
        ),
      );
      _repo.updateTaskStatus(task.id, TaskStatus.cancelled);
      _audit(
        actor,
        action: workforceEvents.authorizationDecided,
        accountId: approval.accountId,
        modelId: approval.modelId,
        result: 'denied',
        detail: 'O operador negou esta execução.',
      );
      _repo.addEvent(execution.id, workforceEvents.authorizationDecided, {
        'result': 'denied',
      });
      _publish(workforceEvents.authorizationDecided, {
        'executionId': execution.id,
        'result': 'denied',
      });
      return taskView(task.id);
    }

    if (action == 'until-limit' && (limitAmount == null || limitAmount <= 0)) {
      throw WorkforceException('Informe o limite aprovado.');
    }
    final requestedModelId = action == 'choose-model'
        ? modelId
        : execution.modelId ?? approval.modelId;
    if (action == 'choose-model' &&
        (requestedModelId == null || requestedModelId.isEmpty)) {
      throw WorkforceException('Escolha um modelo autorizado.');
    }
    if (action != 'choose-model') {
      final plan = execution.planJson == null
          ? null
          : ExecutionPlan.fromJson(
              (jsonDecode(execution.planJson!) as Map).cast<String, Object?>(),
            );
      final modelIds = <String>{
        approval.modelId,
        for (final agent in plan?.agents ?? const <PlanAgent>[]) agent.modelId,
      };
      for (final granted in modelIds) {
        _repo.insertGrant(
          executionId: execution.id,
          accountId: approval.accountId,
          modelId: granted,
          kind: action == 'until-limit' ? 'until-limit' : 'once',
          limitAmount: limitAmount,
        );
      }
    }
    _repo.decideApproval(approval.id, action, limitAmount, 'approved');
    final decision = evaluateStart(
      _evaluationInput(
        task.workspaceId,
        task.projectId,
        execution.id,
        task,
        execution.accountId,
        requestedModelId,
      ),
    );
    _audit(
      actor,
      action: workforceEvents.authorizationDecided,
      accountId: approval.accountId,
      modelId: requestedModelId,
      limitApproved: limitAmount?.toString() ?? action,
      result: 'approved',
      detail: approval.prompt,
    );
    _persistDecision(
      taskId: task.id,
      executionId: execution.id,
      decision: decision,
      actor: actor ?? localOperator,
    );
    return taskView(task.id);
  }

  TaskView pauseTask(String? actor, String taskId) {
    _requireOperator(actor);
    final task = _repo.task(taskId);
    if (task == null)
      throw WorkforceException('Tarefa não encontrada.', code: 'not-found');
    for (final execution in _repo.executionsForTask(taskId)) {
      if (execution.status == ExecutionStatus.cancelled ||
          execution.status == ExecutionStatus.blocked)
        continue;
      _repo.updateExecution(
        execution.id,
        execution.copyWith(
          status: ExecutionStatus.pausedByUser,
          interruptionReason: 'Pausada pelo operador.',
        ),
      );
      _repo.addEvent(execution.id, workforceEvents.executionStateChanged, {
        'status': ExecutionStatus.pausedByUser.value,
      });
    }
    _repo.updateTaskStatus(taskId, TaskStatus.paused);
    _audit(
      actor,
      action: 'execution.pause',
      result: 'paused-by-user',
      detail: task.title,
    );
    return taskView(taskId);
  }

  ResumeResult resumeTask(
    String? actor,
    String taskId, {
    required bool confirmNew,
  }) {
    _requireOperator(actor);
    final task = _repo.task(taskId);
    if (task == null)
      throw WorkforceException('Tarefa não encontrada.', code: 'not-found');
    final executions = _repo.executionsForTask(taskId);
    if (executions.isEmpty)
      throw WorkforceException('Execução não encontrada.', code: 'not-found');
    final execution = executions.last;
    final decision = decideResume(
      status: execution.status,
      sessionId: execution.sessionId,
      resumable: execution.resumable,
    );
    if (decision is RejectResume)
      throw WorkforceException(decision.message, code: 'conflict');
    if (decision is SameSessionResume) {
      _repo.addEvent(execution.id, workforceEvents.resumeRequested, {
        'sessionId': decision.sessionId,
        'applied': false,
      });
      return ResumeResult(
        task: taskView(taskId),
        outcome: decision.outcome,
        applied: false,
        label: decision.label,
        message:
            'A sessão ${decision.sessionId} permanece registrada. O adaptador desta versão não a retomou e nenhuma execução nova foi criada.',
      );
    }
    final fresh = decision as NewExecutionResume;
    if (!confirmNew) {
      _repo.addEvent(execution.id, workforceEvents.resumeRejected, {
        'message': fresh.message,
      });
      return ResumeResult(
        task: taskView(taskId),
        outcome: fresh.outcome,
        applied: false,
        label: fresh.label,
        message: fresh.message,
      );
    }
    final created = _repo.insertExecution(
      taskId: taskId,
      accountId: execution.accountId,
      modelId: execution.modelId,
      status: ExecutionStatus.ready,
      planJson: null,
      interruptionReason: null,
      resumeKind: 'nova execução',
    );
    final next = evaluateStart(
      _evaluationInput(
        task.workspaceId,
        task.projectId,
        created.id,
        task,
        execution.accountId,
        execution.modelId,
      ),
    );
    _persistDecision(
      taskId: taskId,
      executionId: created.id,
      decision: next,
      actor: actor ?? localOperator,
    );
    _audit(
      actor,
      action: 'execution.resume',
      result: 'nova execução',
      detail: 'A sessão original não pôde ser retomada. Foi criada uma execução nova.',
    );
    return ResumeResult(
      task: taskView(taskId),
      outcome: 'new-execution',
      applied: true,
      label: 'nova execução',
      message:
          'Esta execução é nova. Ela não é uma retomada da sessão anterior.',
    );
  }

  List<ModelDefinition> enablePremium(
    String? actor,
    String modelId,
    bool enabled,
  ) {
    _requireOperator(actor);
    if (modelId != 'claude-fable' && modelId != 'cursor-third-party') {
      throw WorkforceException(
        'Só Fable e modelos de terceiro do Cursor exigem esta habilitação.',
      );
    }
    _repo.setOverride(modelId, enabled);
    _audit(
      actor,
      action: 'model.premium',
      modelId: modelId,
      result: enabled ? 'enabled' : 'disabled',
      detail: enabled
          ? 'Habilitação explícita de modelo premium.'
          : 'Modelo premium desabilitado.',
    );
    return resolveCatalog(_repo.overrides());
  }

  List<({ApprovalCategory category, ApprovalMode mode})> setApprovalPolicy(
    String? actor,
    ApprovalCategory category,
    ApprovalMode mode,
  ) {
    _requireOperator(actor);
    _repo.setApprovalMode(category, mode);
    _audit(
      actor,
      action: 'approval.policy',
      result: mode.value,
      detail: 'Categoria ${category.value}.',
    );
    return _repo.approvalPolicies();
  }

  void recordProviderFact(
    String accountId,
    Availability availability,
    AuthState authState,
  ) {
    if (_repo.account(accountId) == null)
      throw WorkforceException('Integração não encontrada.', code: 'not-found');
    _repo.setAvailability(accountId, availability, authState);
    _publish(workforceEvents.availabilityChanged, {
      'accountId': accountId,
      'availability': availability.wire,
      'authState': authState.name,
    });
  }

  PauseTeamResult signalQuota(String accountId) {
    final account = _repo.account(accountId);
    if (account == null)
      throw WorkforceException('Integração não encontrada.', code: 'not-found');
    _repo.setAvailability(
      accountId,
      Availability.quotaExhausted,
      account.authState,
    );
    final open = [
      for (final task in _repo.recentTasks(100))
        for (final execution in _repo.executionsForTask(task.id))
          TeamExecution(
            id: execution.id,
            taskId: execution.taskId,
            accountId: execution.accountId ?? '',
            status: execution.status,
            sessionId: execution.sessionId,
          ),
    ];
    final paused = pauseTeam(
      mode: _repo.organization().mode,
      accountId: accountId,
      reason: 'quota-exhausted',
      executions: open,
      accounts: [
        for (final item in _repo.accounts())
          IntegrationAccount(
            id: item.id,
            provider: item.provider,
            label: item.label,
            billingType: item.billingType,
            authState: item.authState,
            availability: item.availability,
            detectedApiKey: item.detectedApiKey,
            meteredAuthorized: item.meteredAuthorized,
            configured: item.configured,
            authorizedModelIds: const [],
            cliInstalled: false,
          ),
      ],
      models: resolveCatalog(_repo.overrides()),
      policies: const [],
    );
    for (final executionId in paused.executionIds) {
      final execution = _repo.execution(executionId);
      if (execution == null) continue;
      _repo.updateExecution(
        executionId,
        execution.copyWith(
          status: ExecutionStatus.pausedByLimit,
          interruptionReason: paused.message,
        ),
      );
      _repo.addEvent(executionId, workforceEvents.quotaExhausted, {
        'message': paused.message,
      });
      _repo.updateTaskStatus(execution.taskId, TaskStatus.paused);
    }
    _publish(workforceEvents.quotaExhausted, {
      'accountId': accountId,
      'message': paused.message,
    });
    return paused;
  }

  void _persistDecision({
    required String taskId,
    required String executionId,
    required StartDecision decision,
    required String actor,
  }) {
    final plan = switch (decision) {
      ReadyDecision(:final plan) => plan,
      AwaitingAuthorization(:final plan) => plan,
      _ => null,
    };
    final lead = plan?.agents.firstOrNull;
    final provider = lead == null
        ? null
        : _repo.account(lead.accountId)?.provider.wire;
    final current = _repo.execution(executionId);
    if (current != null && plan != null) {
      _repo.updateExecution(
        executionId,
        current.copyWith(
          planJson: jsonEncode(plan.toJson()),
          accountId: lead?.accountId,
          modelId: lead?.modelId,
        ),
      );
    }
    _audit(
      actor,
      action: 'usage.evaluate',
      provider: provider,
      modelId: lead?.modelId,
      accountId: lead?.accountId,
      result: decision.outcome,
      detail: decision.message,
    );

    final stored = _repo.execution(executionId);
    if (stored == null) return;
    switch (decision) {
      case BlockDecision():
        _repo.updateExecution(
          executionId,
          stored.copyWith(
            status: ExecutionStatus.blocked,
            interruptionReason: decision.message,
          ),
        );
        _repo.updateTaskStatus(taskId, TaskStatus.blocked);
        _repo.addEvent(executionId, workforceEvents.executionStateChanged, {
          'status': 'blocked',
          'code': decision.code.value,
          'message': decision.message,
        });
      case PauseTeamDecision():
        _repo.updateExecution(
          executionId,
          stored.copyWith(
            status: ExecutionStatus.pausedByLimit,
            interruptionReason: decision.message,
          ),
        );
        _repo.updateTaskStatus(taskId, TaskStatus.paused);
        _repo.addEvent(executionId, workforceEvents.quotaExhausted, {
          'message': decision.message,
          'alternatives': decision.alternatives
              .map((item) => item.toJson())
              .toList(),
        });
        _publish(workforceEvents.quotaExhausted, {
          'executionId': executionId,
          'message': decision.message,
        });
      case AwaitingAuthorization():
        _repo.updateExecution(
          executionId,
          stored.copyWith(
            status: ExecutionStatus.awaitingAuthorization,
            interruptionReason: decision.prompt,
            accountId: decision.accountId,
            modelId: decision.modelId,
          ),
        );
        _repo.updateTaskStatus(taskId, TaskStatus.awaitingAuthorization);
        if (_repo.pendingApprovalForExecution(executionId) == null) {
          _repo.insertApproval(
            executionId: executionId,
            taskId: taskId,
            prompt: decision.prompt,
            accountId: decision.accountId,
            modelId: decision.modelId,
            alternatives: decision.alternativeModels,
          );
        }
        _repo.addEvent(executionId, workforceEvents.authorizationRequested, {
          'prompt': decision.prompt,
          'accountId': decision.accountId,
          'modelId': decision.modelId,
        });
        _publish(workforceEvents.authorizationRequested, {
          'executionId': executionId,
          'taskId': taskId,
        });
      case ReadyDecision():
        _applyReady(executionId, taskId, decision);
    }
  }

  void _applyReady(String executionId, String taskId, ReadyDecision decision) {
    try {
      startProviderRun();
    } on AdapterNotInstalled catch (error) {
      final current = _repo.execution(executionId);
      if (current != null) {
        _repo.updateExecution(
          executionId,
          current.copyWith(
            status: ExecutionStatus.awaitingAvailability,
            interruptionReason: error.message,
          ),
        );
      }
      _repo.updateTaskStatus(taskId, TaskStatus.awaitingAvailability);
      _repo.addEvent(executionId, workforceEvents.executionStateChanged, {
        'status': 'awaiting-availability',
        'message': error.message,
        'plan': decision.plan.toJson(),
      });
      _publish(workforceEvents.executionStateChanged, {
        'executionId': executionId,
        'status': 'awaiting-availability',
      });
    }
  }

  EvaluateInput _evaluationInput(
    String workspaceId,
    String projectId,
    String executionId,
    TaskRow task,
    String? accountId,
    String? modelId,
  ) {
    final workspace = _repo.workspace(workspaceId);
    final detected = detectMeteredEnv(Platform.environment);
    final installed = probeInstalledClis();
    return EvaluateInput(
      mode: _repo.organization().mode,
      executionId: executionId,
      complexity: task.complexity,
      relevantOperation: task.relevant,
      destructive: task.destructive,
      consumptionPolicy: _repo.approvalMode(ApprovalCategory.consumption),
      accounts: [
        for (final account in _repo.accounts())
          IntegrationAccount(
            id: account.id,
            provider: account.provider,
            label: account.label,
            billingType: account.billingType,
            authState: account.authState,
            availability: account.availability,
            detectedApiKey:
                account.detectedApiKey || (detected[account.provider] ?? false),
            meteredAuthorized: account.meteredAuthorized,
            configured: account.configured,
            authorizedModelIds: _repo.modelIds(
              'workspace',
              workspaceId,
              account.id,
            ),
            cliInstalled: installed[account.provider] ?? false,
          ),
      ],
      models: resolveCatalog(_repo.overrides()),
      policies: [
        for (final policy in _repo.policiesFor([
          'org-local',
          workspaceId,
          projectId,
        ]))
          ScopePolicy(
            scope: policy.scope,
            scopeId: policy.scopeId,
            accountId: policy.accountId,
            decision: policy.decision,
          ),
      ],
      grants: [
        for (final grant in _repo.grantsFor(executionId))
          ConsumptionGrant(
            executionId: grant.executionId,
            accountId: grant.accountId,
            modelId: grant.modelId,
            kind: grant.kind,
            result: 'approved',
            limitAmount: grant.limitAmount,
            consumedAmount: grant.consumedAmount,
          ),
      ],
      agentLimit: workspace?.agentLimit ?? 1,
      requestedAccountId: accountId,
      requestedModelId: modelId,
    );
  }

  String _resolveProjectPath(String projectPath) {
    if (!p.isAbsolute(projectPath)) {
      throw WorkforceException('O caminho do projeto precisa ser absoluto.');
    }
    final directory = Directory(projectPath);
    if (!directory.existsSync()) {
      throw WorkforceException('O diretório do projeto não existe.');
    }
    final stat = directory.statSync();
    if (stat.type != FileSystemEntityType.directory) {
      throw WorkforceException('O caminho precisa ser um diretório.');
    }
    return directory.resolveSymbolicLinksSync();
  }

  void _requireOperator(String? actor) {
    try {
      assertLocalOperator(actor ?? '');
    } on OperatorError catch (error) {
      throw WorkforceException(error.message, code: 'agent-forbidden');
    }
  }

  void _audit(
    String? actor, {
    required String action,
    required String result,
    required String detail,
    String? provider,
    String? modelId,
    String? accountId,
    String? limitApproved,
  }) {
    _repo.audit(
      actor: actor ?? localOperator,
      action: action,
      provider: provider,
      modelId: modelId,
      accountId: accountId,
      limitApproved: limitApproved,
      result: result,
      detail: detail,
    );
  }

  void _publish(String type, Map<String, Object?> payload) {
    if (_events.isClosed) return;
    _events.add(
      WorkforceEvent(
        type: type,
        payload: payload,
        at: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }
}

PolicyDecision? _decisionOf(List<PolicyRow> policies, String accountId) {
  for (final policy in policies) {
    if (policy.accountId == accountId) return policy.decision;
  }
  return null;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
