import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { DatabaseSync } from "node:sqlite";
import { LOCAL_OPERATOR, type ApprovalCategory, type ApprovalMode, type BillingType, type Complexity, type OperationMode, type PolicyDecision } from "@ai-workforce/contracts";
import { migrate } from "./db.js";
import { Repository } from "./repository.js";
import { createService, HttpError, type WorkforceService } from "./service.js";

interface Route {
  method: string;
  pattern: RegExp;
  keys: string[];
  handler: (context: RouteContext) => Promise<void>;
}

interface RouteContext {
  service: WorkforceService;
  params: Record<string, string>;
  body: Record<string, unknown>;
  actor: string | undefined;
  response: ServerResponse;
}

function route(method: string, path: string, handler: Route["handler"]): Route {
  const keys: string[] = [];
  const pattern = new RegExp(
    `^${path.replace(/:([A-Za-z]+)/g, (_match, key: string) => {
      keys.push(key);
      return "([^/]+)";
    })}$`,
  );
  return { method, pattern, keys, handler };
}

async function readBody(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  if (chunks.length === 0) return {};
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  return parsed as Record<string, unknown>;
}

function send(response: ServerResponse, status: number, payload: unknown): void {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  response.end(body);
}

export function createApp(db: DatabaseSync) {
  migrate(db);
  const service = createService(new Repository(db));
  const routes: Route[] = [
    route("GET", "/api/health", async ({ response }) => {
      send(response, 200, { ok: true, service: "ai-workforce", phase: 1 });
    }),
    route("GET", "/api/snapshot", async ({ service: app, response }) => {
      send(response, 200, app.snapshot());
    }),
    route("PATCH", "/api/organization", async ({ service: app, body, actor, response }) => {
      send(response, 200, app.setMode(actor, body.mode as OperationMode));
    }),
    route("POST", "/api/workspaces", async ({ service: app, body, actor, response }) => {
      send(response, 201, app.createWorkspace(actor, String(body.name ?? "")));
    }),
    route("GET", "/api/workspaces/:id", async ({ service: app, params, response }) => {
      send(response, 200, app.workspaceView(params.id ?? ""));
    }),
    route("PUT", "/api/workspaces/:id/policies/:accountId", async ({ service: app, params, body, actor, response }) => {
      send(
        response,
        200,
        app.savePolicy(actor, params.id ?? "", params.accountId ?? "", {
          decision: body.decision as PolicyDecision,
          billingType: (body.billingType as BillingType | null) ?? null,
          label: String(body.label ?? ""),
          authorizedModelIds: Array.isArray(body.authorizedModelIds) ? body.authorizedModelIds.map(String) : [],
          meteredAuthorized: Boolean(body.meteredAuthorized),
        }),
      );
    }),
    route("PUT", "/api/workspaces/:id/budget", async ({ service: app, params, body, actor, response }) => {
      const limit = body.limitAmount === null || body.limitAmount === undefined || body.limitAmount === "" ? null : Number(body.limitAmount);
      send(response, 200, app.setBudget(actor, params.id ?? "", limit));
    }),
    route("POST", "/api/workspaces/:id/projects", async ({ service: app, params, body, actor, response }) => {
      send(response, 201, app.createProject(actor, params.id ?? "", String(body.name ?? ""), String(body.path ?? "")));
    }),
    route("GET", "/api/projects/:id", async ({ service: app, params, response }) => {
      send(response, 200, app.projectView(params.id ?? ""));
    }),
    route("POST", "/api/projects/:id/tasks", async ({ service: app, params, body, actor, response }) => {
      send(
        response,
        201,
        app.createTask(actor, params.id ?? "", {
          title: String(body.title ?? ""),
          complexity: body.complexity as Complexity,
          relevantOperation: Boolean(body.relevantOperation),
          destructive: Boolean(body.destructive),
          ...(body.accountId ? { accountId: String(body.accountId) } : {}),
          ...(body.modelId ? { modelId: String(body.modelId) } : {}),
        }),
      );
    }),
    route("GET", "/api/tasks/:id", async ({ service: app, params, response }) => {
      send(response, 200, app.taskView(params.id ?? ""));
    }),
    route("POST", "/api/tasks/:id/pause", async ({ service: app, params, actor, response }) => {
      send(response, 200, app.pauseTask(actor, params.id ?? ""));
    }),
    route("POST", "/api/tasks/:id/resume", async ({ service: app, params, body, actor, response }) => {
      send(response, 200, app.resumeTask(actor, params.id ?? "", Boolean(body.confirmNew)));
    }),
    route("GET", "/api/approvals", async ({ service: app, response }) => {
      send(response, 200, app.snapshot().approvals);
    }),
    route("POST", "/api/approvals/:id", async ({ service: app, params, body, actor, response }) => {
      send(
        response,
        200,
        app.decideApproval(actor, params.id ?? "", {
          action: body.action as "once" | "until-limit" | "deny" | "choose-model",
          ...(body.modelId ? { modelId: String(body.modelId) } : {}),
          ...(body.limitAmount ? { limitAmount: Number(body.limitAmount) } : {}),
        }),
      );
    }),
    route("POST", "/api/models/:id/enabled", async ({ service: app, params, body, actor, response }) => {
      send(response, 200, app.enablePremium(actor, params.id ?? "", Boolean(body.enabled)));
    }),
    route("PUT", "/api/approval-policies/:category", async ({ service: app, params, body, actor, response }) => {
      send(response, 200, app.setApprovalPolicy(actor, params.category as ApprovalCategory, body.mode as ApprovalMode));
    }),
    route("GET", "/api/audit", async ({ service: app, response }) => {
      send(response, 200, app.snapshot().audit);
    }),
  ];

  const server = createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    const actorHeader = request.headers["x-ai-workforce-actor"];
    const actor = Array.isArray(actorHeader) ? actorHeader[0] : actorHeader;
    try {
      const match = routes.find((item) => item.method === request.method && item.pattern.test(url.pathname));
      if (!match) {
        send(response, 404, { error: "Rota não encontrada." });
        return;
      }
      const found = match.pattern.exec(url.pathname);
      const params: Record<string, string> = {};
      match.keys.forEach((key, index) => {
        params[key] = decodeURIComponent(found?.[index + 1] ?? "");
      });
      const body = request.method === "GET" ? {} : await readBody(request);
      await match.handler({
        service,
        params,
        body,
        actor: actor ?? (request.method === "GET" ? LOCAL_OPERATOR : undefined),
        response,
      });
    } catch (error) {
      if (error instanceof HttpError) {
        send(response, error.status, { error: error.message, code: error.code });
        return;
      }
      if (error instanceof SyntaxError) {
        send(response, 400, { error: "JSON inválido." });
        return;
      }
      send(response, 500, { error: "Falha interna." });
    }
  });

  return { server, service };
}
