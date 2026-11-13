import { describe, expect, it } from "vitest";
import { blockedMeteredEnv, type IntegrationAccount, type ModelDefinition, type ScopePolicy } from "@ai-workforce/contracts";
import { modelCatalog, resolveCatalog } from "./catalog.js";
import { detectMeteredEnv, sanitizeEnv } from "./env.js";
import { assertLocalOperator, decideResume, evaluateStart, pauseTeam, type EvaluateInput } from "./manager.js";

const models = resolveCatalog({});

function account(partial: Partial<IntegrationAccount> & Pick<IntegrationAccount, "id" | "provider">): IntegrationAccount {
  return {
    label: partial.id,
    billingType: "corporate-subscription",
    authState: "authenticated",
    availability: "available",
    detectedApiKey: false,
    meteredAuthorized: false,
    configured: true,
    authorizedModelIds: [],
    cliInstalled: true,
    ...partial,
  };
}

const claude = account({
  id: "claude",
  provider: "claude-code",
  label: "Claude corporativo",
  billingType: "corporate-subscription",
  authorizedModelIds: ["claude-haiku", "claude-sonnet", "claude-opus"],
});

function allow(accountId: string, decision: ScopePolicy["decision"] = "allow"): ScopePolicy {
  return { scope: "workspace", scopeId: "sti3", accountId, decision };
}

function base(partial: Partial<EvaluateInput> = {}): EvaluateInput {
  return {
    mode: "economic",
    executionId: "exec-1",
    complexity: "simple",
    relevantOperation: false,
    destructive: false,
    consumptionPolicy: "automatic",
    accounts: [claude],
    models,
    policies: [allow("claude")],
    grants: [],
    ...partial,
  };
}

describe("cenários de aceite", () => {
  it("executa o ciclo na assinatura corporativa autorizada", () => {
    const decision = evaluateStart(base());
    expect(decision.outcome).toBe("ready");
    if (decision.outcome !== "ready") return;
    expect(decision.plan.phases).toEqual(["analyze", "plan", "implement", "review"]);
    expect(decision.plan.agents).toEqual([{ role: "executor", accountId: "claude", modelId: "claude-haiku" }]);
    expect(decision.plan.sameAccount).toBe(true);
    expect(new Set(decision.plan.agents.map((agent) => agent.accountId))).toEqual(new Set(["claude"]));
  });

  it("bloqueia Claude sem autenticação", () => {
    const decision = evaluateStart(
      base({ accounts: [{ ...claude, authState: "unauthenticated" }] }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "unauthenticated" });
  });

  it("pausa a equipe quando a quota acaba e não oferece API paga", () => {
    const metered = account({
      id: "claude-api",
      provider: "claude-code",
      billingType: "metered-api",
      detectedApiKey: true,
      meteredAuthorized: false,
      authorizedModelIds: ["claude-haiku"],
    });
    const decision = evaluateStart(
      base({
        accounts: [{ ...claude, availability: "quota-exhausted" }, metered],
        policies: [allow("claude"), allow("claude-api")],
      }),
    );
    expect(decision.outcome).toBe("pause-team");
    if (decision.outcome !== "pause-team") return;
    expect(decision.alternatives).toEqual([]);
    expect(decision.preserveSession).toBe(true);
  });

  it("pede autorização quando a disponibilidade é desconhecida", () => {
    const decision = evaluateStart(base({ accounts: [{ ...claude, availability: "unknown" }] }));
    expect(decision.outcome).toBe("awaiting-authorization");
  });

  it("trata integração ainda não verificada como disponibilidade não comprovada", () => {
    const decision = evaluateStart(
      base({
        mode: "restricted",
        accounts: [{ ...claude, authState: "disconnected", availability: "not-probed" }],
      }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "unproven-availability" });
  });

  it("bloqueia disponibilidade desconhecida no modo restrito", () => {
    const decision = evaluateStart(
      base({ mode: "restricted", accounts: [{ ...claude, availability: "unknown" }] }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "unproven-availability" });
  });

  it("mantém a API key detectada bloqueada", () => {
    const metered = account({
      id: "claude-api",
      provider: "claude-code",
      label: "Claude API",
      billingType: "metered-api",
      detectedApiKey: true,
      authorizedModelIds: ["claude-haiku"],
    });
    const decision = evaluateStart(
      base({
        requestedAccountId: "claude-api",
        accounts: [claude, metered],
        policies: [allow("claude"), allow("claude-api")],
      }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "metered-blocked" });
  });

  it("não trata a API key detectada como substituta da assinatura", () => {
    const decision = evaluateStart(base({ accounts: [{ ...claude, detectedApiKey: true }] }));
    expect(decision.outcome).toBe("ready");
  });

  it("bloqueia modelo fora da lista do workspace", () => {
    const decision = evaluateStart(
      base({
        mode: "balanced",
        requestedModelId: "claude-opus",
        accounts: [{ ...claude, authorizedModelIds: ["claude-haiku"] }],
      }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "model-denied" });
  });

  it("pausa o Copilot quando os créditos acabam", () => {
    const copilot = account({
      id: "copilot",
      provider: "copilot",
      label: "Copilot pessoal",
      billingType: "provider-credits",
      availability: "quota-exhausted",
      authorizedModelIds: ["copilot-economy"],
    });
    const decision = evaluateStart(
      base({
        accounts: [copilot],
        policies: [allow("copilot", "allow-with-approval")],
      }),
    );
    expect(decision.outcome).toBe("pause-team");
    if (decision.outcome !== "pause-team") return;
    expect(decision.message).toContain("créditos");
  });

  it("pausa a equipe inteira e preserva a sessão quando a integração cai", () => {
    const result = pauseTeam({
      mode: "economic",
      accountId: "claude",
      reason: "disconnected",
      executions: [
        { id: "a", taskId: "task", accountId: "claude", status: "ready", sessionId: "sess-1" },
        { id: "b", taskId: "task", accountId: "claude", status: "awaiting-availability", sessionId: null },
      ],
      accounts: [claude],
      models,
      policies: [allow("claude")],
    });
    expect(result.executionIds).toEqual(["a", "b"]);
    expect(result.preserveSession).toBe(true);
    expect(result.message).toContain("desconectou");
  });

  it("retoma a mesma sessão e recusa chamar uma execução nova de retomada", () => {
    expect(decideResume({ status: "paused-by-limit", sessionId: "sess-1", resumable: true })).toEqual({
      outcome: "same-session",
      sessionId: "sess-1",
      label: "retomada",
    });
    const fresh = decideResume({ status: "paused-by-limit", sessionId: null, resumable: false });
    expect(fresh.outcome).toBe("new-execution");
    if (fresh.outcome !== "new-execution") return;
    expect(fresh.label).toBe("nova execução");
  });

  it("não faz fallback para provedor negado no workspace", () => {
    const codex = account({
      id: "codex",
      provider: "codex",
      billingType: "personal-subscription",
      authorizedModelIds: ["codex-economy"],
    });
    const decision = evaluateStart(
      base({
        accounts: [{ ...claude, availability: "quota-exhausted" }, codex],
        policies: [allow("claude"), allow("codex", "deny")],
      }),
    );
    expect(decision.outcome).toBe("pause-team");
    if (decision.outcome !== "pause-team") return;
    expect(decision.alternatives).toEqual([]);
  });
});

describe("modos e uma assinatura", () => {
  it("no modo econômico pede aprovação para arquitetura e segue com um agente econômico", () => {
    const waiting = evaluateStart(base({ complexity: "architecture" }));
    expect(waiting.outcome).toBe("awaiting-authorization");
    if (waiting.outcome !== "awaiting-authorization") return;
    expect(waiting.modelId).toBe("claude-haiku");
    expect(waiting.alternativeModels.map((model) => model.id)).not.toContain("claude-opus");

    const ready = evaluateStart(
      base({
        complexity: "architecture",
        grants: [{ executionId: "exec-1", accountId: "claude", modelId: "claude-haiku", kind: "once", result: "approved" }],
      }),
    );
    expect(ready.outcome).toBe("ready");
    if (ready.outcome !== "ready") return;
    expect(ready.plan.agents).toHaveLength(1);
  });

  it("não reaproveita autorização de outra execução", () => {
    const decision = evaluateStart(
      base({
        executionId: "exec-2",
        complexity: "architecture",
        grants: [{ executionId: "exec-1", accountId: "claude", modelId: "claude-haiku", kind: "once", result: "approved" }],
      }),
    );
    expect(decision.outcome).toBe("awaiting-authorization");
  });

  it("no modo equilibrado monta a equipe dentro da mesma conta", () => {
    const decision = evaluateStart(base({ mode: "balanced", complexity: "architecture", agentLimit: 4 }));
    expect(decision.outcome).toBe("ready");
    if (decision.outcome !== "ready") return;
    expect(decision.plan.agents.map((agent) => agent.role)).toEqual(["architect", "developer", "reviewer"]);
    expect(decision.plan.agents.every((agent) => agent.accountId === "claude")).toBe(true);
    expect(decision.plan.agents.map((agent) => agent.modelId)).toEqual(["claude-opus", "claude-sonnet", "claude-haiku"]);
  });

  it("respeita o limite de agentes do workspace", () => {
    const decision = evaluateStart(base({ mode: "balanced", complexity: "architecture", agentLimit: 1 }));
    expect(decision.outcome).toBe("ready");
    if (decision.outcome !== "ready") return;
    expect(decision.plan.agents).toHaveLength(1);
  });

  it("uma tarefa simples usa um agente mesmo no modo equilibrado", () => {
    const decision = evaluateStart(base({ mode: "balanced", complexity: "simple" }));
    expect(decision.outcome).toBe("ready");
    if (decision.outcome !== "ready") return;
    expect(decision.plan.agents).toHaveLength(1);
    expect(decision.plan.agents[0]?.modelId).toBe("claude-haiku");
  });

  it("não eleva o modo econômico para um modelo intermediário", () => {
    const decision = evaluateStart(
      base({ accounts: [{ ...claude, authorizedModelIds: ["claude-sonnet"] }] }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "no-economy-model" });
  });

  it("negação do workspace impede a permissão da organização", () => {
    const decision = evaluateStart(
      base({
        policies: [
          { scope: "organization", scopeId: "org", accountId: "claude", decision: "allow" },
          allow("claude", "deny"),
        ],
      }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "not-authorized" });
  });

  it("uma permissão ampla não afrouxa a exigência de aprovação", () => {
    const decision = evaluateStart(
      base({
        policies: [
          { scope: "organization", scopeId: "org", accountId: "claude", decision: "allow-with-approval" },
          allow("claude", "allow"),
        ],
      }),
    );
    expect(decision.outcome).toBe("awaiting-authorization");
  });

  it("conta conectada sem política não autoriza consumo", () => {
    const decision = evaluateStart(base({ policies: [] }));
    expect(decision).toMatchObject({ outcome: "block", code: "not-authorized" });
  });

  it("mantém Fable desabilitado", () => {
    const decision = evaluateStart(
      base({
        mode: "balanced",
        requestedModelId: "claude-fable",
        accounts: [{ ...claude, authorizedModelIds: [...claude.authorizedModelIds, "claude-fable"] }],
      }),
    );
    expect(decision).toMatchObject({ outcome: "block", code: "premium-disabled" });
  });

  it("usa Fable só depois de habilitação explícita e fora do modo econômico", () => {
    const enabled = resolveCatalog({ "claude-fable": true });
    const economic = evaluateStart(
      base({
        models: enabled,
        requestedModelId: "claude-fable",
        accounts: [{ ...claude, authorizedModelIds: ["claude-fable", "claude-haiku"] }],
      }),
    );
    expect(economic).toMatchObject({ outcome: "block", code: "model-denied" });

    const balanced = evaluateStart(
      base({
        mode: "balanced",
        models: enabled,
        requestedModelId: "claude-fable",
        accounts: [{ ...claude, authorizedModelIds: ["claude-fable"] }],
        grants: [{ executionId: "exec-1", accountId: "claude", modelId: "claude-fable", kind: "once", result: "approved" }],
      }),
    );
    expect(balanced.outcome).toBe("ready");
  });
});

describe("proteção de credenciais e operador", () => {
  it("remove variáveis de cobrança medida do ambiente do processo", () => {
    const clean = sanitizeEnv(
      {
        PATH: "/usr/bin",
        ANTHROPIC_API_KEY: "sk-secret",
        OPENAI_API_KEY: "sk-secret",
        COPILOT_PROVIDER_API_KEY: "sk-secret",
      },
      false,
    );
    expect(clean.PATH).toBe("/usr/bin");
    for (const key of blockedMeteredEnv) expect(clean[key]).toBeUndefined();
    expect(JSON.stringify(clean)).not.toContain("sk-secret");
  });

  it("detecta presença de chave sem devolver o valor", () => {
    const detected = detectMeteredEnv({ ANTHROPIC_API_KEY: "sk-secret", PATH: "/usr/bin" });
    expect(detected["claude-code"]).toBe(true);
    expect(detected.codex).toBe(false);
    expect(JSON.stringify(detected)).not.toContain("sk-secret");
  });

  it("impede um agente de autorizar ou alterar política", () => {
    expect(() => assertLocalOperator("agent")).toThrow(/não pode autorizar/);
    expect(() => assertLocalOperator("local-operator")).not.toThrow();
  });
});

describe("catálogo", () => {
  it("não afirma disponibilidade de modelos concretos sem probe", () => {
    const unbound = modelCatalog.filter((model) => model.provider !== "claude-code");
    expect(unbound.every((model) => model.cliAlias === null)).toBe(true);
    const fable = modelCatalog.find((model) => model.id === "claude-fable") as ModelDefinition;
    expect(fable.enabled).toBe(false);
  });
});
