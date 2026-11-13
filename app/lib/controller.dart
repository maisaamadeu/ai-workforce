import 'package:flutter/foundation.dart';
import 'package:workforce_core/workforce_core.dart';

enum AppDestination {
  dashboard,
  usage,
  approvals,
  diagnostics,
  workspace,
  project,
  task,
}

class WorkforceController extends ChangeNotifier {
  WorkforceController(this.workforce) {
    refresh();
  }

  final LocalWorkforce workforce;
  Snapshot? snapshot;
  WorkspaceView? workspace;
  ProjectView? project;
  TaskView? task;
  String? error;
  String? notice;
  AppDestination destination = AppDestination.dashboard;
  bool dark = false;

  void refresh() {
    snapshot = workforce.snapshot();
    notifyListeners();
  }

  void toggleTheme() {
    dark = !dark;
    notifyListeners();
  }

  void go(AppDestination next) {
    destination = next;
    error = null;
    notifyListeners();
  }

  void guard(void Function() action) {
    try {
      error = null;
      action();
      snapshot = workforce.snapshot();
    } on WorkforceException catch (caught) {
      error = caught.message;
      snapshot = workforce.snapshot();
    }
    notifyListeners();
  }

  void setMode(OperationMode mode) =>
      guard(() => workforce.setMode(localOperator, mode));

  void createWorkspace(String name) =>
      guard(() => workforce.createWorkspace(localOperator, name));

  void openWorkspace(String id) {
    guard(() {
      workspace = workforce.workspaceView(id);
      destination = AppDestination.workspace;
    });
  }

  void createProject(String name, String path) {
    final id = workspace?.workspace.id;
    if (id == null) return;
    guard(() {
      workforce.createProject(localOperator, id, name, path);
      workspace = workforce.workspaceView(id);
    });
  }

  void saveBudget(String raw) {
    final id = workspace?.workspace.id;
    if (id == null) return;
    final trimmed = raw.trim();
    double? amount;
    if (trimmed.isNotEmpty) {
      amount = double.tryParse(trimmed.replaceAll(',', '.'));
      if (amount == null) {
        error = 'O teto precisa ser um número maior que zero.';
        notifyListeners();
        return;
      }
    }
    guard(() {
      workforce.setBudget(localOperator, id, amount);
      workspace = workforce.workspaceView(id);
    });
  }

  void savePolicy({
    required String accountId,
    required PolicyDecision decision,
    required BillingType? billingType,
    required String label,
    required List<String> modelIds,
    required bool meteredAuthorized,
  }) {
    final id = workspace?.workspace.id;
    if (id == null) return;
    guard(() {
      workspace = workforce.savePolicy(
        localOperator,
        id,
        accountId,
        decision: decision,
        billingType: billingType,
        label: label,
        authorizedModelIds: modelIds,
        meteredAuthorized: meteredAuthorized,
      );
    });
  }

  void openProject(String id) {
    guard(() {
      project = workforce.projectView(id);
      destination = AppDestination.project;
    });
  }

  void createTask({
    required String title,
    required Complexity complexity,
    required bool relevant,
    required bool destructive,
  }) {
    final id = project?.project.id;
    if (id == null) return;
    guard(() {
      task = workforce.createTask(
        localOperator,
        id,
        title: title,
        complexity: complexity,
        relevantOperation: relevant,
        destructive: destructive,
      );
      project = workforce.projectView(id);
      destination = AppDestination.task;
    });
  }

  void openTask(String id) {
    guard(() {
      task = workforce.taskView(id);
      destination = AppDestination.task;
    });
  }

  void pauseTask() {
    final id = task?.task.id;
    if (id == null) return;
    guard(() => task = workforce.pauseTask(localOperator, id));
  }

  void resumeTask({required bool confirmNew}) {
    final id = task?.task.id;
    if (id == null) return;
    guard(() {
      final result = workforce.resumeTask(
        localOperator,
        id,
        confirmNew: confirmNew,
      );
      task = result.task;
      notice = result.message;
    });
  }

  void decide(String approvalId, String action) {
    guard(() {
      task = workforce.decideApproval(
        localOperator,
        approvalId,
        action: action,
      );
      if (destination != AppDestination.task) {
        destination = AppDestination.approvals;
      }
    });
  }

  void enablePremium(String modelId, bool enabled) =>
      guard(() => workforce.enablePremium(localOperator, modelId, enabled));
}
