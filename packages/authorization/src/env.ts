import { blockedMeteredEnv, type ProviderId } from "@ai-workforce/contracts";

const detectedByProvider: Record<ProviderId, readonly string[]> = {
  "claude-code": ["ANTHROPIC_API_KEY"],
  codex: ["OPENAI_API_KEY"],
  cursor: ["CURSOR_API_KEY"],
  copilot: ["COPILOT_PROVIDER_API_KEY", "COPILOT_PROVIDER_BASE_URL", "COPILOT_PROVIDER_TYPE"],
};

export function sanitizeEnv(source: NodeJS.ProcessEnv, allowMetered: boolean): NodeJS.ProcessEnv {
  const next: NodeJS.ProcessEnv = { ...source };
  if (!allowMetered) {
    for (const key of blockedMeteredEnv) delete next[key];
  }
  return next;
}

export function detectMeteredEnv(source: NodeJS.ProcessEnv): Record<ProviderId, boolean> {
  const result: Record<ProviderId, boolean> = {
    "claude-code": false,
    codex: false,
    cursor: false,
    copilot: false,
  };
  for (const provider of Object.keys(detectedByProvider) as ProviderId[]) {
    result[provider] = detectedByProvider[provider].some((key) => {
      const value = source[key];
      return typeof value === "string" && value.length > 0;
    });
  }
  return result;
}
