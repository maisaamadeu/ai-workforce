import 'package:material_ui/material_ui.dart';
import 'package:workforce_core/workforce_core.dart';

import 'controller.dart';
import 'screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AiWorkforceApp(workforce: LocalWorkforce.open()));
}

class AiWorkforceApp extends StatefulWidget {
  const AiWorkforceApp({required this.workforce, super.key});

  final LocalWorkforce workforce;

  @override
  State<AiWorkforceApp> createState() => _AiWorkforceAppState();
}

class _AiWorkforceAppState extends State<AiWorkforceApp> {
  late final WorkforceController controller = WorkforceController(
    widget.workforce,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final seed = const Color(0xFF1F4D3A);
        return MaterialApp(
          title: 'AI Workforce',
          debugShowCheckedModeBanner: false,
          themeMode: controller.dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: WorkforceShell(controller: controller),
        );
      },
    );
  }
}

class WorkforceShell extends StatelessWidget {
  const WorkforceShell({required this.controller, super.key});

  final WorkforceController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final approvals = snapshot?.approvals.length ?? 0;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: _railIndex(controller.destination),
            onDestinationSelected: (index) =>
                controller.go(_destinations[index]),
            leading: const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'AI Workforce',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(
                    onPressed: controller.toggleTheme,
                    child: Text(controller.dark ? 'Tema claro' : 'Tema escuro'),
                  ),
                ),
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                label: Text('Painel'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.speed_outlined),
                label: Text('Uso e limites'),
              ),
              NavigationRailDestination(
                icon: Badge(
                  isLabelVisible: approvals > 0,
                  label: Text('$approvals'),
                  child: const Icon(Icons.rule_outlined),
                ),
                label: Text(
                  approvals > 0 ? 'Aprovações ($approvals)' : 'Aprovações',
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                label: Text('Diagnóstico'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<OperationMode>(
                        segments: const [
                          ButtonSegment(
                            value: OperationMode.economic,
                            label: Text('Econômico'),
                          ),
                          ButtonSegment(
                            value: OperationMode.balanced,
                            label: Text('Equilibrado'),
                          ),
                          ButtonSegment(
                            value: OperationMode.restricted,
                            label: Text('Restrito'),
                          ),
                        ],
                        selected: {
                          snapshot?.organization.mode ?? OperationMode.economic,
                        },
                        onSelectionChanged: (selection) =>
                            controller.setMode(selection.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        modeCopy[snapshot?.organization.mode ??
                            OperationMode.economic]!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (controller.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(child: ScreenBody(controller: controller)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _destinations = [
  AppDestination.dashboard,
  AppDestination.usage,
  AppDestination.approvals,
  AppDestination.diagnostics,
];

int _railIndex(AppDestination destination) {
  final index = _destinations.indexOf(destination);
  return index < 0 ? 0 : index;
}
