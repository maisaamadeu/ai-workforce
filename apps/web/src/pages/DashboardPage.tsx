import { useState } from "react";
import { Link } from "react-router-dom";
import { api, type Snapshot } from "../api";
import { statusLabel, tagClass } from "../labels";

export function DashboardPage({ snapshot, onChange }: { snapshot: Snapshot | null; onChange: () => void }) {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function createWorkspace(event: React.FormEvent) {
    event.preventDefault();
    try {
      await api.createWorkspace(name);
      setName("");
      onChange();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Falha ao criar workspace.");
    }
  }

  const paused = snapshot?.tasks.filter((task) => task.status === "paused" || task.status.startsWith("paused")).length ?? 0;

  return (
    <div className="stack">
      <div>
        <h1>Painel</h1>
        <p className="meta">Nenhum provedor é chamado nesta versão. Disponibilidade não verificada não vira percentual.</p>
      </div>
      <section className="grid">
        <article className="panel stat"><b>{snapshot?.workspaces.length ?? "—"}</b><span>Workspaces</span></article>
        <article className="panel stat"><b>{snapshot?.tasks.length ?? "—"}</b><span>Tarefas recentes</span></article>
        <article className="panel stat"><b>{snapshot?.approvals.length ?? "—"}</b><span>Aprovações pendentes</span></article>
        <article className="panel stat"><b>{paused}</b><span>Tarefas pausadas</span></article>
      </section>
      <div className="grid-2">
        <section className="panel stack">
          <h2>Workspaces</h2>
          <form className="row" onSubmit={(event) => void createWorkspace(event)}>
            <label className="field" style={{ flex: 1 }}>
              Nome
              <input value={name} onChange={(event) => setName(event.target.value)} placeholder="STi3" />
            </label>
            <button className="button primary" type="submit">Criar</button>
          </form>
          {error ? <p className="error">{error}</p> : null}
          <div className="list">
            {snapshot?.workspaces.map((workspace) => (
              <Link key={workspace.id} to={`/workspaces/${workspace.id}`}>
                <span>{workspace.name}</span>
                <span className="meta">{workspace.projectCount} projetos</span>
              </Link>
            ))}
            {snapshot && snapshot.workspaces.length === 0 ? <p className="meta">Nenhum workspace ainda.</p> : null}
          </div>
        </section>
        <section className="panel stack">
          <h2>Integrações</h2>
          <div className="list">
            {snapshot?.integrations.map((integration) => (
              <div className="item" key={integration.id}>
                <span>{integration.label}</span>
                <span className="tag">{integration.cliInstalled ? "CLI no PATH" : "CLI ausente"}</span>
              </div>
            ))}
          </div>
          <p className="meta">Autenticação e quota ainda não foram consultadas.</p>
        </section>
      </div>
      <section className="panel">
        <h2>Tarefas recentes</h2>
        <div className="list">
          {snapshot?.tasks.map((task) => (
            <Link key={task.id} to={`/tasks/${task.id}`}>
              <span>{task.title}</span>
              <span className={tagClass(task.status)}>{statusLabel[task.status] ?? task.status}</span>
            </Link>
          ))}
          {snapshot && snapshot.tasks.length === 0 ? <p className="meta">Nenhuma tarefa registrada.</p> : null}
        </div>
      </section>
    </div>
  );
}
