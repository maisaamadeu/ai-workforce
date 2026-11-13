import 'contracts.dart';

const modelCatalog = <ModelDefinition>[
  ModelDefinition(
    id: 'claude-haiku',
    provider: ProviderId.claudeCode,
    name: 'Haiku',
    modelClass: ModelClass.economy,
    enabled: true,
    cliAlias: 'haiku',
  ),
  ModelDefinition(
    id: 'claude-sonnet',
    provider: ProviderId.claudeCode,
    name: 'Sonnet',
    modelClass: ModelClass.standard,
    enabled: true,
    cliAlias: 'sonnet',
  ),
  ModelDefinition(
    id: 'claude-opus',
    provider: ProviderId.claudeCode,
    name: 'Opus',
    modelClass: ModelClass.reasoning,
    enabled: true,
    cliAlias: 'opus',
  ),
  ModelDefinition(
    id: 'claude-fable',
    provider: ProviderId.claudeCode,
    name: 'Fable',
    modelClass: ModelClass.explicitPremium,
    enabled: false,
    cliAlias: 'fable',
  ),
  ModelDefinition(
    id: 'codex-economy',
    provider: ProviderId.codex,
    name: 'Codex econômico',
    modelClass: ModelClass.economy,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'codex-standard',
    provider: ProviderId.codex,
    name: 'Codex intermediário',
    modelClass: ModelClass.standard,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'codex-reasoning',
    provider: ProviderId.codex,
    name: 'Codex raciocínio',
    modelClass: ModelClass.reasoning,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'cursor-composer',
    provider: ProviderId.cursor,
    name: 'Composer',
    modelClass: ModelClass.economy,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'cursor-grok',
    provider: ProviderId.cursor,
    name: 'Grok',
    modelClass: ModelClass.standard,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'cursor-third-party',
    provider: ProviderId.cursor,
    name: 'Modelo de terceiro',
    modelClass: ModelClass.explicitPremium,
    enabled: false,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'copilot-economy',
    provider: ProviderId.copilot,
    name: 'Copilot econômico',
    modelClass: ModelClass.economy,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'copilot-standard',
    provider: ProviderId.copilot,
    name: 'Copilot intermediário',
    modelClass: ModelClass.standard,
    enabled: true,
    cliAlias: null,
  ),
  ModelDefinition(
    id: 'copilot-reasoning',
    provider: ProviderId.copilot,
    name: 'Copilot raciocínio',
    modelClass: ModelClass.reasoning,
    enabled: true,
    cliAlias: null,
  ),
];

const premiumIds = {'claude-fable', 'cursor-third-party'};

List<ModelDefinition> resolveCatalog(Map<String, bool> overrides) {
  return modelCatalog.map((model) {
    final override = overrides[model.id];
    if (override == null || !premiumIds.contains(model.id)) return model;
    return model.copyWith(enabled: override);
  }).toList();
}
