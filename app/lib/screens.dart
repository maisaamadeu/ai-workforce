import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:workforce_core/workforce_core.dart';

import 'controller.dart';
import 'labels.dart';
import 'platform_info.dart';

class ScreenBody extends StatelessWidget {
  const ScreenBody({required this.controller, super.key});
  final WorkforceController controller;

  @override
  Widget build(BuildContext context) {
    final child = switch (controller.destination) {
      AppDestination.dashboard => DashboardScreen(controller: controller),
      AppDestination.usage => UsageScreen(controller: controller),
      AppDestination.approvals => ApprovalsScreen(controller: controller),
      AppDestination.diagnostics => DiagnosticsScreen(controller: controller),
      AppDestination.workspace => WorkspaceScreen(controller: controller),
      AppDestination.project => ProjectScreen(controller: controller),
      AppDestination.task => TaskScreen(controller: controller),
    };
    return ListView(padding: const EdgeInsets.all(28), children: [child]);
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    final paused =
        snapshot?.tasks
            .where((task) => task.status == TaskStatus.paused)
            .length ??
        0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Painel', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        const Text(
          'Nenhum provedor é chamado nesta versão. Disponibilidade não verificada não vira percentual.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Stat('${snapshot?.workspaces.length ?? '—'}', 'Workspaces'),
            _Stat('${snapshot?.tasks.length ?? '—'}', 'Tarefas recentes'),
            _Stat(
              '${snapshot?.approvals.length ?? '—'}',
              'Aprovações pendentes',
            ),
            _Stat('$paused', 'Tarefas pausadas'),
          ],
        ),
        const SizedBox(height: 20),
        Text('Workspaces', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('workspace-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () {
                widget.controller.createWorkspace(_name.text);
                _name.clear();
              },
              child: const Text('Criar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (snapshot != null && snapshot.workspaces.isEmpty)
          const Text('Nenhum workspace ainda.'),
        for (final workspace in snapshot?.workspaces ?? const <WorkspaceRow>[])
          ListTile(
            title: Text(workspace.name),
            subtitle: Text('${workspace.projectCount} projetos'),
            onTap: () => widget.controller.openWorkspace(workspace.id),
          ),
        const SizedBox(height: 12),
        Text('Integrações', style: Theme.of(context).textTheme.titleLarge),
        for (final integration
            in snapshot?.integrations ?? const <IntegrationView>[])
          ListTile(
            title: Text(integration.account.label),
            trailing: Text(
              integration.cliInstalled ? 'CLI no PATH' : 'CLI ausente',
            ),
          ),
        const Text('Autenticação e quota ainda não foram consultadas.'),
        const SizedBox(height: 12),
        Text('Tarefas recentes', style: Theme.of(context).textTheme.titleLarge),
        if (snapshot != null && snapshot.tasks.isEmpty)
          const Text('Nenhuma tarefa registrada.'),
        for (final task in snapshot?.tasks ?? const <TaskRow>[])
          ListTile(
            title: Text(task.title),
            trailing: Text(statusLabel(task.status.value)),
            onTap: () => widget.controller.openTask(task.id),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _projectName = TextEditingController();
  final _projectPath = TextEditingController();
  final _budget = TextEditingController();
  String? _loadedId;

  @override
  void initState() {
    super.initState();
    _syncBudget();
  }

  @override
  void didUpdateWidget(covariant WorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBudget();
  }

  void _syncBudget() {
    final detail = widget.controller.workspace;
    if (detail == null || _loadedId == detail.workspace.id) return;
    _loadedId = detail.workspace.id;
    _budget.text = detail.budget == null
        ? ''
        : detail.budget!.limitAmount.toString();
  }

  @override
  void dispose() {
    _projectName.dispose();
    _projectPath.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.controller.workspace;
    if (detail == null) return const Text('Workspace não carregado.');
    final models =
        widget.controller.snapshot?.models ?? const <ModelDefinition>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => widget.controller.go(AppDestination.dashboard),
          child: const Text('Voltar ao painel'),
        ),
        Text(
          detail.workspace.name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          'Limite de agentes no modo equilibrado: ${detail.workspace.agentLimit}. Projetos do workspace não misturam código.',
        ),
        const SizedBox(height: 16),
        Text('Projetos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _projectName,
          decoration: const InputDecoration(
            labelText: 'Nome',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('project-path'),
          controller: _projectPath,
          decoration: const InputDecoration(
            labelText: 'Diretório absoluto',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () {
            widget.controller.createProject(
              _projectName.text,
              _projectPath.text,
            );
            _projectName.clear();
            _projectPath.clear();
          },
          child: const Text('Registrar'),
        ),
        const SizedBox(height: 4),
        const Text(
          'O registro guarda o caminho. A análise do repositório fica para o onboarding.',
        ),
        for (final project in detail.projects)
          ListTile(
            title: Text(project.name),
            subtitle: Text(project.path),
            onTap: () => widget.controller.openProject(project.id),
          ),
        const SizedBox(height: 16),
        Text(
          'Teto de tokens observados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _budget,
          decoration: const InputDecoration(
            labelText: 'Limite opcional nesta aplicação',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => widget.controller.saveBudget(_budget.text),
          child: const Text('Gravar teto'),
        ),
        const Text(
          'Este número não é a quota do provedor. Sem estimativa, o modo restrito bloqueia a tarefa quando há teto.',
        ),
        const SizedBox(height: 16),
        Text(
          'Políticas de consumo',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final policy in detail.policies)
          PolicyEditor(
            key: ValueKey(
              '${policy.accountId}-${policy.decision?.value}-${policy.authorizedModelIds.join(',')}',
            ),
            policy: policy,
            models: models
                .where(
                  (model) => model.provider == policy.provider && model.enabled,
                )
                .toList(),
            onSave: widget.controller.savePolicy,
          ),
        const SizedBox(height: 16),
        Text('Tarefas', style: Theme.of(context).textTheme.titleLarge),
        for (final task in detail.tasks)
          ListTile(
            title: Text(task.title),
            trailing: Text(statusLabel(task.status.value)),
            onTap: () => widget.controller.openTask(task.id),
          ),
      ],
    );
  }
}

class PolicyEditor extends StatefulWidget {
  const PolicyEditor({
    required this.policy,
    required this.models,
    required this.onSave,
    super.key,
  });

  final AccountPolicyView policy;
  final List<ModelDefinition> models;
  final void Function({
    required String accountId,
    required PolicyDecision decision,
    required BillingType? billingType,
    required String label,
    required List<String> modelIds,
    required bool meteredAuthorized,
  })
  onSave;

  @override
  State<PolicyEditor> createState() => _PolicyEditorState();
}

class _PolicyEditorState extends State<PolicyEditor> {
  late PolicyDecision decision = widget.policy.decision ?? PolicyDecision.deny;
  late BillingType? billing = widget.policy.billingType;
  late final TextEditingController label = TextEditingController(
    text: widget.policy.label,
  );
  late final Set<String> models = {...widget.policy.authorizedModelIds};
  late bool metered = widget.policy.meteredAuthorized;

  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.policy.provider.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: label,
              decoration: const InputDecoration(
                labelText: 'Rótulo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButton<PolicyDecision>(
              value: decision,
              items: [
                for (final item in PolicyDecision.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(decisionLabel(item)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => decision = value ?? decision),
            ),
            DropdownButton<BillingType?>(
              value: billing,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tipo de cobrança não declarado'),
                ),
                for (final item in BillingType.values)
                  DropdownMenuItem(value: item, child: Text(item.label)),
              ],
              onChanged: (value) => setState(() => billing = value),
            ),
            for (final model in widget.models)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(model.name),
                value: models.contains(model.id),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    models.add(model.id);
                  } else {
                    models.remove(model.id);
                  }
                }),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Autorizar cobrança medida'),
              value: metered,
              onChanged: (checked) =>
                  setState(() => metered = checked ?? false),
            ),
            FilledButton(
              onPressed: () => widget.onSave(
                accountId: widget.policy.accountId,
                decision: decision,
                billingType: billing,
                label: label.text,
                modelIds: models.toList(),
                meteredAuthorized: metered,
              ),
              child: const Text('Salvar política'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  final _title = TextEditingController();
  Complexity complexity = Complexity.simple;
  bool relevant = false;
  bool destructive = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const Text('Projeto não carregado.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () =>
              widget.controller.openWorkspace(project.project.workspaceId),
          child: const Text('Voltar ao workspace'),
        ),
        Text(
          project.project.name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(project.project.path),
        const SizedBox(height: 16),
        TextField(
          key: const Key('task-title'),
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Tarefa',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<Complexity>(
          value: complexity,
          items: [
            for (final item in Complexity.values)
              DropdownMenuItem(value: item, child: Text(complexityLabel(item))),
          ],
          onChanged: (value) =>
              setState(() => complexity = value ?? complexity),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Operação relevante'),
          value: relevant,
          onChanged: (value) => setState(() => relevant = value ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Operação destrutiva'),
          value: destructive,
          onChanged: (value) => setState(() => destructive = value ?? false),
        ),
        FilledButton(
          onPressed: () => widget.controller.createTask(
            title: _title.text,
            complexity: complexity,
            relevant: relevant,
            destructive: destructive,
          ),
          child: const Text('Submeter'),
        ),
        const SizedBox(height: 12),
        for (final task in project.tasks)
          ListTile(
            title: Text(task.title),
            trailing: Text(statusLabel(task.status.value)),
            onTap: () => widget.controller.openTask(task.id),
          ),
      ],
    );
  }
}

class TaskScreen extends StatelessWidget {
  const TaskScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  Widget build(BuildContext context) {
    final view = controller.task;
    if (view == null) return const Text('Tarefa não carregada.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => controller.openProject(view.task.projectId),
          child: const Text('Voltar ao projeto'),
        ),
        Text(
          view.task.title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          '${statusLabel(view.task.status.value)} · ${complexityLabel(view.task.complexity)}',
        ),
        if (controller.notice != null) ...[
          const SizedBox(height: 8),
          Text(controller.notice!),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: controller.pauseTask,
              child: const Text('Pausar'),
            ),
            OutlinedButton(
              onPressed: () => controller.resumeTask(confirmNew: false),
              child: const Text('Retomar'),
            ),
            OutlinedButton(
              onPressed: () => controller.resumeTask(confirmNew: true),
              child: const Text('Confirmar nova execução'),
            ),
          ],
        ),
        for (final execution in view.executions) ...[
          const SizedBox(height: 16),
          Text(
            statusLabel(execution.execution.status.value),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (execution.execution.interruptionReason != null)
            Text(execution.execution.interruptionReason!),
          if (execution.execution.resumeKind != null)
            Text(execution.execution.resumeKind!),
          if (execution.plan != null) ...[
            Text(execution.plan!.phases.map(phaseLabel).join(' → ')),
            for (final agent in execution.plan!.agents)
              Text(
                '${roleLabel(agent.role)} · ${agent.modelId} · ${agent.accountId}',
              ),
          ],
          if (execution.approval != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(execution.approval!.prompt),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () =>
                              controller.decide(execution.approval!.id, 'once'),
                          child: const Text('Autorizar uma vez'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              controller.decide(execution.approval!.id, 'deny'),
                          child: const Text('Negar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class UsageScreen extends StatelessWidget {
  const UsageScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uso e limites',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Tokens, créditos, estimativa e quota ficam em linhas separadas. Valor ausente permanece como não medido.',
        ),
        const SizedBox(height: 12),
        for (final integration
            in snapshot?.integrations ?? const <IntegrationView>[])
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          integration.account.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(integration.availabilityLabel),
                    ],
                  ),
                  Text(
                    '${integration.account.billingType?.label ?? 'Tipo de cobrança não declarado'} · ${integration.cliInstalled ? 'CLI encontrado no PATH' : 'CLI não encontrado no PATH'} · ${integration.account.meteredAuthorized ? 'Cobrança medida autorizada' : 'API paga bloqueada'}',
                  ),
                  if (integration.detectedApiKey)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Uma chave de API foi detectada no ambiente. O valor não é exibido e ela permanece bloqueada como alternativa.',
                      ),
                    ),
                  const SizedBox(height: 8),
                  for (final meter in integration.usage)
                    Text('${meter.unit.label}: ${usageAmount(meter)}'),
                ],
              ),
            ),
          ),
        Text('Modelos premium', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Fable e modelos de terceiro do Cursor nascem desabilitados. Habilitar é uma decisão explícita e auditada.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => controller.enablePremium('claude-fable', true),
              child: const Text('Habilitar Fable'),
            ),
            OutlinedButton(
              onPressed: () =>
                  controller.enablePremium('cursor-third-party', true),
              child: const Text('Habilitar modelo de terceiro'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Auditoria', style: Theme.of(context).textTheme.titleLarge),
        for (final entry in snapshot?.audit ?? const <AuditRow>[])
          ListTile(
            title: Text(
              '${entry.action} · ${entry.result}${entry.limitApproved == null ? '' : ' · ${entry.limitApproved}'}',
            ),
            subtitle: Text('${formatStamp(entry.at)} · ${entry.detail}'),
          ),
      ],
    );
  }
}

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  Widget build(BuildContext context) {
    final approvals = controller.snapshot?.approvals ?? const <ApprovalRow>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Aprovações', style: Theme.of(context).textTheme.headlineMedium),
        if (approvals.isEmpty) const Text('Nenhuma autorização pendente.'),
        for (final approval in approvals)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(approval.prompt),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => controller.decide(approval.id, 'once'),
                        child: const Text('Autorizar uma vez'),
                      ),
                      OutlinedButton(
                        onPressed: () => controller.decide(approval.id, 'deny'),
                        child: const Text('Negar'),
                      ),
                      TextButton(
                        onPressed: () => controller.openTask(approval.taskId),
                        child: const Text('Abrir tarefa'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({required this.controller, super.key});
  final WorkforceController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diagnóstico', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Sistema: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        ),
        Text('Arquitetura: ${architectureLabel()}'),
        Text('Diretório de dados: ${snapshot?.dataDirectory ?? '—'}'),
        Text('Schema: ${snapshot?.schemaVersion ?? '—'}'),
        Text('Supervisor: ${supervisorLabel()}'),
        Text('Cofre: ${credentialLabel()}'),
        const Text('Atualização automática: indisponível nesta versão.'),
        const Text('Licença: uso local, sem cobrança.'),
        const SizedBox(height: 12),
        for (final integration
            in snapshot?.integrations ?? const <IntegrationView>[])
          Text(
            '${integration.account.provider.label}: binário ${integration.account.provider.binary} ${integration.cliInstalled ? 'encontrado' : 'ausente'} · ${integration.availabilityLabel}',
          ),
      ],
    );
  }
}
