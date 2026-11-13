import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type PolicyInput, type Snapshot, type WorkspaceDetail } from "../api";
import { billingLabel, statusLabel, tagClass } from "../labels";

export function WorkspacePage({ onChange }: { onChange: () => void }) {
  const { id = "" } = useParams();
  const [detail, setDetail] = useState<WorkspaceDetail | null>(null);
  const [models, setModels] = useState<Snapshot["models"]>([]);
  const [error, setError] = useState<string | null>(null);
  const [projectName, setProjectName] = useState("");
  const [projectPath, setProjectPath] = useState("");
  const [budget, setBudget] = useState("");

  async function load() {
    const [workspace, snapshot] = await Promise.all([api.workspace(id), api.snapshot()]);
    setDetail(workspace);
    setModels(snapshot.models);
    setBudget(workspace.budget ? String(workspace.budget.limitAmount) : "");
  }

  useEffect(() => {
    load().catch((reason: Error) => setError(reason.message));
  }, [id]);

  async function createProject(event: React.FormEvent) {
    event.preventDefault();
    try {
      await api.createProject(id, projectName, projectPath);
      setProjectName("");
      setProjectPath("");
      await load();
      onChange();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Falha ao registrar projeto.");
    }
  }

  async function saveBudget(event: React.FormEvent) {
    event.preventDefault();
    try {
      await api.setBudget(id, budget.trim() === "" ? null : Number(budget));
      await load();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Falha ao gravar teto.");
    }
  }

  if (!detail) return <p className="meta">{error ?? "Carregando workspace."}</p>;

  return (
    <div className="stack">
      <div>
        <h1>{detail.workspace.name}</h1>
        <p className="meta">Limite de agentes no modo equilibrado: {detail.workspace.agentLimit}. Projetos do workspace não misturam código.</p>
      </div>
      {error ? <p className="error">{error}</p> : null}
      <section className="panel stack">
        <h2>Projetos</h2>
        <form className="row" onSubmit={(event) => void createProject(event)}>
          <label className="field">Nome<input value={projectName} onChange={(event) => setProjectName(event.target.value)} placeholder="KDS" /></label>
          <label className="field" style={{ flex: 1 }}>Diretório absoluto<input value={projectPath} onChange={(event) => setProjectPath(event.target.value)} placeholder="/caminho/do/repositorio" /></label>
          <button className="button primary" type="submit">Registrar</button>
        </form>
        <p className="meta">O registro guarda o caminho. A análise do repositório fica para o onboarding.</p>
        <div className="list">
          {detail.projects.map((project) => (
            <Link key={project.id} to={`/projects/${project.id}`}>
              <span>{project.name}</span>
              <span className="meta">{project.path}</span>
            </Link>
          ))}
        </div>
      </section>
      <section className="panel stack">
        <h2>Teto de tokens observados</h2>
        <form className="row" onSubmit={(event) => void saveBudget(event)}>
          <label className="field">
            Limite opcional nesta aplicação
            <input value={budget} onChange={(event) => setBudget(event.target.value)} inputMode="numeric" placeholder="vazio = sem teto" />
          </label>
          <button className="button" type="submit">Gravar</button>
        </form>
        <p className="meta">Este número não é a quota do provedor. Sem estimativa, o modo restrito bloqueia a tarefa quando há teto.</p>
      </section>
      <section className="stack">
        <h2>Políticas de consumo</h2>
        {detail.policies.map((policy) => (
          <PolicyCard key={policy.accountId} workspaceId={id} policy={policy} models={models.filter((model) => model.provider === policy.provider)} onSaved={() => void load()} />
        ))}
      </section>
      <section className="panel">
        <h2>Tarefas</h2>
        <div className="list">
          {detail.tasks.map((task) => (
            <Link key={task.id} to={`/tasks/${task.id}`}>
              <span>{task.title}</span>
              <span className={tagClass(task.status)}>{statusLabel[task.status] ?? task.status}</span>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}

function PolicyCard({
  workspaceId,
  policy,
  models,
  onSaved,
}: {
  workspaceId: string;
  policy: WorkspaceDetail["policies"][number];
  models: Snapshot["models"];
  onSaved: () => void;
}) {
  const [decision, setDecision] = useState<PolicyInput["decision"]>(policy.decision ?? "deny");
  const [billingType, setBillingType] = useState(policy.billingType ?? "");
  const [label, setLabel] = useState(policy.label);
  const [selected, setSelected] = useState<string[]>(policy.authorizedModelIds);
  const [metered, setMetered] = useState(policy.meteredAuthorized);
  const [message, setMessage] = useState<string | null>(null);

  function toggle(modelId: string) {
    setSelected((current) => (current.includes(modelId) ? current.filter((item) => item !== modelId) : [...current, modelId]));
  }

  async function save(event: React.FormEvent) {
    event.preventDefault();
    try {
      await api.savePolicy(workspaceId, policy.accountId, {
        decision,
        billingType: billingType || null,
        label,
        authorizedModelIds: selected,
        meteredAuthorized: metered,
      });
      setMessage("Política gravada.");
      onSaved();
    } catch (reason) {
      setMessage(reason instanceof Error ? reason.message : "Falha ao gravar.");
    }
  }

  return (
    <form className="panel stack" onSubmit={(event) => void save(event)}>
      <div className="row" style={{ justifyContent: "space-between" }}>
        <h2 style={{ margin: 0 }}>{policy.label}</h2>
        <span className="tag">{policy.configured ? "Configurada" : "Sem política"}</span>
      </div>
      <div className="row">
        <label className="field">Rótulo<input value={label} onChange={(event) => setLabel(event.target.value)} /></label>
        <label className="field">
          Cobrança
          <select value={billingType} onChange={(event) => setBillingType(event.target.value)}>
            <option value="">Não declarada</option>
            {Object.entries(billingLabel).map(([value, text]) => <option key={value} value={value}>{text}</option>)}
          </select>
        </label>
        <label className="field">
          Decisão
          <select value={decision} onChange={(event) => setDecision(event.target.value as PolicyInput["decision"])}>
            <option value="deny">Negar</option>
            <option value="allow-with-approval">Permitir com autorização</option>
            <option value="allow">Permitir</option>
          </select>
        </label>
      </div>
      <div className="checks">
        {models.map((model) => (
          <label key={model.id}>
            <input type="checkbox" checked={selected.includes(model.id)} disabled={!model.enabled} onChange={() => toggle(model.id)} />
            {model.name} · {model.modelClass}
            {model.enabled ? "" : " · desabilitado até autorização explícita"}
            {model.cliAlias ? "" : " · alias concreto depende do probe"}
          </label>
        ))}
      </div>
      <label className="checks">
        <span>
          <input type="checkbox" checked={metered} onChange={(event) => setMetered(event.target.checked)} />
          Autorizar cobrança medida desta conta
        </span>
      </label>
      <div className="row">
        <button className="button primary" type="submit">Salvar política</button>
        {message ? <span className="meta">{message}</span> : null}
      </div>
    </form>
  );
}
