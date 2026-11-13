import { mkdtempSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { openDatabase } from "./db.js";
import { createApp } from "./http.js";

const projectPath = mkdtempSync(join(tmpdir(), "ai-workforce-project-"));
const servers: Array<ReturnType<typeof createApp>["server"]> = [];

async function start() {
  const db = openDatabase(":memory:");
  const app = createApp(db);
  servers.push(app.server);
  await new Promise<void>((resolve) => app.server.listen(0, "127.0.0.1", () => resolve()));
  const address = app.server.address() as AddressInfo;
  return { base: `http://127.0.0.1:${address.port}`, service: app.service };
}

afterEach(async () => {
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise<void>((resolve) => {
          server.close(() => resolve());
        }),
    ),
  );
});

function actor(extra?: Record<string, string>): HeadersInit {
  return { "content-type": "application/json", "x-ai-workforce-actor": "local-operator", ...extra };
}

describe("API local", () => {
  it("não chama provedor e estaciona a tarefa autorizada sem consumo", async () => {
    const { base } = await start();
    const workspace = await request(base, "POST", "/api/workspaces", { name: "STi3" });
    await request(base, "PUT", `/api/workspaces/${workspace.id}/policies/acc-claude`, {
      decision: "allow",
      billingType: "corporate-subscription",
      label: "Claude corporativo",
      authorizedModelIds: ["claude-haiku"],
      meteredAuthorized: false,
    });
    const project = await request(base, "POST", `/api/workspaces/${workspace.id}/projects`, {
      name: "KDS",
      path: projectPath,
    });
    const created = await request(base, "POST", `/api/projects/${project.id}/tasks`, {
      title: "Mapear o fluxo atual",
      complexity: "simple",
    });
    expect(created.task.status).toBe("awaiting-authorization");
    const approvalId = created.executions[0].approval.id as string;
    const decided = await request(base, "POST", `/api/approvals/${approvalId}`, { action: "once" });
    expect(decided.task.status).toBe("awaiting-availability");
    expect(decided.executions.at(-1).interruptionReason).toContain("Nenhuma chamada foi feita");
    expect(decided.executions.at(-1).events.some((event: { type: string }) => event.type === "execution.state.changed")).toBe(true);
    const usage = await request(base, "GET", "/api/snapshot");
    const claude = usage.integrations.find((item: { id: string }) => item.id === "acc-claude");
    expect(claude.availability).toBe("not-probed");
    expect(claude.usage.every((meter: { amount: number | null }) => meter.amount === null)).toBe(true);
  });

  it("bloqueia no modo restrito enquanto a disponibilidade não foi verificada", async () => {
    const { base } = await start();
    await request(base, "PATCH", "/api/organization", { mode: "restricted" });
    const workspace = await request(base, "POST", "/api/workspaces", { name: "STi3" });
    await request(base, "PUT", `/api/workspaces/${workspace.id}/policies/acc-claude`, {
      decision: "allow",
      billingType: "corporate-subscription",
      label: "Claude corporativo",
      authorizedModelIds: ["claude-haiku"],
      meteredAuthorized: false,
    });
    const project = await request(base, "POST", `/api/workspaces/${workspace.id}/projects`, {
      name: "KDS",
      path: projectPath,
    });
    const created = await request(base, "POST", `/api/projects/${project.id}/tasks`, {
      title: "Revisar o contrato",
      complexity: "simple",
    });
    expect(created.task.status).toBe("blocked");
    expect(created.executions[0].interruptionReason).toContain("modo restrito");
  });

  it("pausa quando a quota já está registrada e não escolhe outra conta", async () => {
    const { base, service } = await start();
    const workspace = await request(base, "POST", "/api/workspaces", { name: "STi3" });
    await request(base, "PUT", `/api/workspaces/${workspace.id}/policies/acc-claude`, {
      decision: "allow",
      billingType: "corporate-subscription",
      label: "Claude corporativo",
      authorizedModelIds: ["claude-haiku", "claude-sonnet", "claude-opus"],
      meteredAuthorized: false,
    });
    await request(base, "PUT", `/api/workspaces/${workspace.id}/policies/acc-codex`, {
      decision: "deny",
      billingType: "personal-subscription",
      label: "Codex pessoal",
      authorizedModelIds: [],
      meteredAuthorized: false,
    });
    service.recordProviderFact("acc-claude", "quota-exhausted", "authenticated");
    const authed = service.snapshot().integrations.find((item: { id: string }) => item.id === "acc-claude");
    expect(authed.availability).toBe("quota-exhausted");
    const project = await request(base, "POST", `/api/workspaces/${workspace.id}/projects`, {
      name: "KDS",
      path: projectPath,
    });
    const created = await request(base, "POST", `/api/projects/${project.id}/tasks`, {
      title: "Continuar depois da quota",
      complexity: "architecture",
    });
    expect(created.task.status).toBe("paused");
    const quotaEvent = created.executions[0].events.find((event: { type: string }) => event.type === "usage.quota.exhausted");
    expect(quotaEvent.payload.alternatives).toEqual([]);
  });

  it("impede um agente de alterar política e identifica execução nova", async () => {
    const { base } = await start();
    const workspace = await request(base, "POST", "/api/workspaces", { name: "STi3" });
    const denied = await fetch(`${base}/api/workspaces/${workspace.id}/policies/acc-claude`, {
      method: "PUT",
      headers: { "content-type": "application/json", "x-ai-workforce-actor": "agent" },
      body: JSON.stringify({
        decision: "allow",
        billingType: "corporate-subscription",
        label: "Claude",
        authorizedModelIds: ["claude-haiku"],
        meteredAuthorized: true,
      }),
    });
    expect(denied.status).toBe(403);

    await request(base, "PUT", `/api/workspaces/${workspace.id}/policies/acc-claude`, {
      decision: "allow",
      billingType: "corporate-subscription",
      label: "Claude corporativo",
      authorizedModelIds: ["claude-haiku"],
      meteredAuthorized: false,
    });
    const project = await request(base, "POST", `/api/workspaces/${workspace.id}/projects`, { name: "KDS", path: projectPath });
    const created = await request(base, "POST", `/api/projects/${project.id}/tasks`, { title: "Pausar", complexity: "simple" });
    const approvalId = created.executions[0].approval.id as string;
    const decided = await request(base, "POST", `/api/approvals/${approvalId}`, { action: "once" });
    const paused = await request(base, "POST", `/api/tasks/${decided.task.id}/pause`, {});
    expect(paused.task.status).toBe("paused");
    const asked = await request(base, "POST", `/api/tasks/${decided.task.id}/resume`, { confirmNew: false });
    expect(asked.resume.outcome).toBe("new-execution");
    expect(asked.resume.applied).toBe(false);
    const resumed = await request(base, "POST", `/api/tasks/${decided.task.id}/resume`, { confirmNew: true });
    expect(resumed.resume.label).toBe("nova execução");
    expect(resumed.resume.message).toContain("não é uma retomada");
    expect(resumed.task.executions.at(-1).resumeKind).toBe("nova execução");
  });

  it("rejeita diretório inexistente e não vaza segredo detectado", async () => {
    const previous = process.env.ANTHROPIC_API_KEY;
    process.env.ANTHROPIC_API_KEY = "sk-test-secret";
    try {
      const { base } = await start();
      const workspace = await request(base, "POST", "/api/workspaces", { name: "STi3" });
      const missing = await fetch(`${base}/api/workspaces/${workspace.id}/projects`, {
        method: "POST",
        headers: actor(),
        body: JSON.stringify({ name: "KDS", path: join(projectPath, "nao-existe") }),
      });
      expect(missing.status).toBe(400);
      const snapshot = await request(base, "GET", "/api/snapshot");
      const body = JSON.stringify(snapshot);
      expect(body).not.toContain("sk-test-secret");
      expect(snapshot.integrations.find((item: { id: string }) => item.id === "acc-claude").detectedApiKey).toBe(true);
    } finally {
      if (previous === undefined) delete process.env.ANTHROPIC_API_KEY;
      else process.env.ANTHROPIC_API_KEY = previous;
    }
  });
});

async function request(base: string, method: string, path: string, body?: unknown): Promise<any> {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: actor(),
    body: body === undefined || method === "GET" ? undefined : JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(`${method} ${path} -> ${response.status} ${JSON.stringify(payload)}`);
  return payload;
}

