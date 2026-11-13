import type { ModelDefinition, ProviderId } from "@ai-workforce/contracts";

/**
 * Catálogo local de classes e aliases estáveis.
 * `cliAlias` nulo significa que o identificador concreto ainda depende do
 * probe do CLI. Nada aqui afirma disponibilidade na conta.
 */
export const modelCatalog: readonly ModelDefinition[] = [
  { id: "claude-haiku", provider: "claude-code", name: "Haiku", modelClass: "economy", enabled: true, cliAlias: "haiku" },
  { id: "claude-sonnet", provider: "claude-code", name: "Sonnet", modelClass: "standard", enabled: true, cliAlias: "sonnet" },
  { id: "claude-opus", provider: "claude-code", name: "Opus", modelClass: "reasoning", enabled: true, cliAlias: "opus" },
  { id: "claude-fable", provider: "claude-code", name: "Fable", modelClass: "explicit-premium", enabled: false, cliAlias: "fable" },
  { id: "codex-economy", provider: "codex", name: "Codex econômico", modelClass: "economy", enabled: true, cliAlias: null },
  { id: "codex-standard", provider: "codex", name: "Codex intermediário", modelClass: "standard", enabled: true, cliAlias: null },
  { id: "codex-reasoning", provider: "codex", name: "Codex raciocínio", modelClass: "reasoning", enabled: true, cliAlias: null },
  { id: "cursor-composer", provider: "cursor", name: "Composer", modelClass: "economy", enabled: true, cliAlias: null },
  { id: "cursor-grok", provider: "cursor", name: "Grok", modelClass: "standard", enabled: true, cliAlias: null },
  { id: "cursor-third-party", provider: "cursor", name: "Modelo de terceiro", modelClass: "explicit-premium", enabled: false, cliAlias: null },
  { id: "copilot-economy", provider: "copilot", name: "Copilot econômico", modelClass: "economy", enabled: true, cliAlias: null },
  { id: "copilot-standard", provider: "copilot", name: "Copilot intermediário", modelClass: "standard", enabled: true, cliAlias: null },
  { id: "copilot-reasoning", provider: "copilot", name: "Copilot raciocínio", modelClass: "reasoning", enabled: true, cliAlias: null },
];

const premiumIds = new Set(["claude-fable", "cursor-third-party"]);

export function resolveCatalog(overrides: ReadonlyMap<string, boolean> | Record<string, boolean>): ModelDefinition[] {
  const table = overrides instanceof Map ? overrides : new Map(Object.entries(overrides));
  return modelCatalog.map((model) => {
    const override = table.get(model.id);
    if (override === undefined) return model;
    if (!premiumIds.has(model.id)) return model;
    return { ...model, enabled: override };
  });
}

export function modelsForProvider(models: readonly ModelDefinition[], provider: ProviderId): ModelDefinition[] {
  return models.filter((model) => model.provider === provider);
}
