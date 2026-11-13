export const statusLabel: Record<string, string> = {
  open: "Aberta",
  blocked: "Bloqueada",
  paused: "Pausada",
  "awaiting-authorization": "Aguardando autorização",
  "awaiting-availability": "Aguardando disponibilidade",
  "paused-by-user": "Pausada pelo operador",
  "paused-by-limit": "Pausada por limite",
  cancelling: "Cancelando",
  cancelled: "Cancelada",
  ready: "Pronta",
  failed: "Falhou",
};

export const complexityLabel: Record<string, string> = {
  simple: "Simples",
  standard: "Intermediária",
  architecture: "Arquitetura",
};

export const roleLabel: Record<string, string> = {
  executor: "Executor",
  architect: "Arquiteto",
  developer: "Desenvolvedor",
  reviewer: "Revisor",
};

export const phaseLabel: Record<string, string> = {
  analyze: "Analisar",
  plan: "Planejar",
  implement: "Implementar",
  review: "Revisar",
};

export const billingLabel: Record<string, string> = {
  "personal-subscription": "Assinatura pessoal",
  "corporate-subscription": "Assinatura corporativa",
  "metered-api": "API com cobrança por utilização",
  "provider-credits": "Créditos do provedor",
  unmetered: "Sem contabilização do provedor",
};

export const unitLabel: Record<string, string> = {
  "app-tokens": "Tokens desta aplicação",
  "provider-credits": "Créditos do provedor",
  "estimated-usd": "Custo estimado",
  "provider-quota": "Quota informada pelo provedor",
};

export const categoryLabel: Record<string, string> = {
  consumption: "Consumo de modelo",
  "skill-install": "Instalar skill",
  mcp: "Adicionar MCP",
  "admin-command": "Comando administrativo",
  "config-file": "Arquivo de configuração",
  "global-instructions": "Instruções globais",
  "delete-files": "Excluir arquivos",
  migration: "Migração",
  "git-destructive": "Git destrutivo",
  "cross-project": "Acessar outro projeto",
  "extra-resources": "Recurso adicional",
};

export const modeCopy: Record<string, string> = {
  economic: "Usa modelos econômicos, evita delegação e pede aprovação para operações relevantes.",
  balanced: "Permite equipe quando a complexidade justifica, dentro dos limites da tarefa e do workspace.",
  restricted: "Só modelos e contas já autorizados. Disponibilidade desconhecida bloqueia a partida.",
};

export function tagClass(status: string): string {
  if (status.includes("pause") || status === "awaiting-authorization" || status === "awaiting-availability") return "tag warn";
  if (status === "blocked" || status === "cancelled" || status === "failed") return "tag danger";
  if (status === "ready" || status === "open") return "tag ok";
  return "tag";
}
