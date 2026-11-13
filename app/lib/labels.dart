import 'package:workforce_core/workforce_core.dart';

String statusLabel(String value) {
  return switch (value) {
    'open' => 'Aberta',
    'blocked' => 'Bloqueada',
    'paused' => 'Pausada',
    'awaiting-authorization' => 'Aguardando autorização',
    'awaiting-availability' => 'Aguardando disponibilidade',
    'paused-by-user' => 'Pausada pelo operador',
    'paused-by-limit' => 'Pausada por limite',
    'cancelling' => 'Cancelando',
    'cancelled' => 'Cancelada',
    'ready' => 'Pronta',
    'failed' => 'Falhou',
    _ => value,
  };
}

String complexityLabel(Complexity complexity) {
  return switch (complexity) {
    Complexity.simple => 'Simples',
    Complexity.standard => 'Intermediária',
    Complexity.architecture => 'Arquitetura',
  };
}

String categoryLabel(ApprovalCategory category) {
  return switch (category) {
    ApprovalCategory.consumption => 'Consumo de modelo',
    ApprovalCategory.skillInstall => 'Instalar skill',
    ApprovalCategory.mcp => 'Adicionar MCP',
    ApprovalCategory.adminCommand => 'Comando administrativo',
    ApprovalCategory.configFile => 'Arquivo de configuração',
    ApprovalCategory.globalInstructions => 'Instruções globais',
    ApprovalCategory.deleteFiles => 'Excluir arquivos',
    ApprovalCategory.migration => 'Migração',
    ApprovalCategory.gitDestructive => 'Git destrutivo',
    ApprovalCategory.crossProject => 'Acessar outro projeto',
    ApprovalCategory.extraResources => 'Recurso adicional',
  };
}

String roleLabel(AgentRole role) {
  return switch (role) {
    AgentRole.executor => 'Executor',
    AgentRole.architect => 'Arquiteto',
    AgentRole.developer => 'Desenvolvedor',
    AgentRole.reviewer => 'Revisor',
  };
}

String phaseLabel(Phase phase) {
  return switch (phase) {
    Phase.analyze => 'Analisar',
    Phase.plan => 'Planejar',
    Phase.implement => 'Implementar',
    Phase.review => 'Revisar',
  };
}

String decisionLabel(PolicyDecision decision) {
  return switch (decision) {
    PolicyDecision.allow => 'Autorizar',
    PolicyDecision.allowWithApproval => 'Autorizar com aprovação',
    PolicyDecision.deny => 'Negar',
  };
}

String formatStamp(String iso) {
  final parsed = DateTime.tryParse(iso)?.toUtc();
  if (parsed == null) return iso;
  final local = parsed.subtract(const Duration(hours: 3));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)} (Brasília)';
}

String usageAmount(ObservedUsage usage) =>
    usage.amount == null ? 'Não medido' : usage.amount.toString();
