import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { api, type TaskView } from "../api";
import { phaseLabel, roleLabel, statusLabel, tagClass } from "../labels";

export function TaskPage({ onChange }: { onChange: () => void }) {
  const { id = "" } = useParams();
  const [view, setView] = useState<TaskView | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [canConfirmNew, setCanConfirmNew] = useState(false);
  const [limit, setLimit] = useState("100000");
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setView(await api.task(id));
  }

  useEffect(() => {
    load().catch((reason: Error) => setError(reason.message));
  }, [id]);

  async function act(body: Record<string, unknown>) {
    const approval = view?.executions.find((execution) => execution.approval)?.approval;
    if (!approval) return;
    try {
      setView(await api.decide(approval.id, body));
      onChange();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Falha na autorização.");
    }
  }

  async function pause() {
    setView(await api.pause(id));
    onChange();
  }

  async function resume(confirmNew: boolean) {
    const result = await api.resume(id, confirmNew);
    setView(result.task);
    setNotice(result.resume.message);
    setCanConfirmNew(result.resume.outcome === "new-execution" && !result.resume.applied);
    onChange();
  }

  if (!view) return <p className="meta">{error ?? "Carregando tarefa."}</p>;
  const execution = view.executions.at(-1);
  const approval = view.executions.map((item) => item.approval).find(Boolean);
  const alternatives = approval ? (JSON.parse(approval.alternativesJson) as Array<{ id: string; name: string }>) : [];

  return (
    <div className="stack">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <h1>{view.task.title}</h1>
        <span className={tagClass(view.task.status)}>{statusLabel[view.task.status] ?? view.task.status}</span>
      </div>
      {error ? <p className="error">{error}</p> : null}
      {notice ? <p className="callout">{notice}</p> : null}
      {execution?.interruptionReason ? <p className="callout warn">{execution.interruptionReason}</p> : null}
      {execution?.resumeKind ? <p className="meta">Identificação: {execution.resumeKind}</p> : null}
      {execution?.plan ? (
        <section className="panel stack">
          <h2>Plano na mesma conta</h2>
          <p>{execution.plan.phases.map((phase) => phaseLabel[phase] ?? phase).join(" → ")}</p>
          <div className="list">
            {execution.plan.agents.map((agent) => (
              <div className="item" key={`${agent.role}-${agent.modelId}`}>
                <span>{roleLabel[agent.role] ?? agent.role}</span>
                <span className="meta">{agent.modelId}</span>
              </div>
            ))}
          </div>
        </section>
      ) : null}
      {approval ? (
        <section className="panel stack">
          <h2>Autorização</h2>
          <p>{approval.prompt}</p>
          <div className="row">
            <button className="button primary" type="button" onClick={() => void act({ action: "once" })}>Autorizar uma vez</button>
            <label className="field">
              Limite de tokens observados
              <input value={limit} onChange={(event) => setLimit(event.target.value)} />
            </label>
            <button className="button" type="button" onClick={() => void act({ action: "until-limit", limitAmount: Number(limit) })}>Autorizar até o limite</button>
            <button className="button" type="button" onClick={() => void act({ action: "deny" })}>Negar</button>
          </div>
          {alternatives.length > 0 ? (
            <div className="row">
              {alternatives.map((model) => (
                <button key={model.id} className="button" type="button" onClick={() => void act({ action: "choose-model", modelId: model.id })}>
                  Usar {model.name}
                </button>
              ))}
            </div>
          ) : <p className="meta">Não há outro modelo autorizado nesta conta para o modo atual.</p>}
        </section>
      ) : null}
      <div className="row">
        <button className="button" type="button" onClick={() => void pause()}>Pausar</button>
        <button className="button" type="button" onClick={() => void resume(false)}>Ver retomada</button>
        {canConfirmNew ? <button className="button primary" type="button" onClick={() => void resume(true)}>Autorizar execução nova</button> : null}
      </div>
      <section className="panel">
        <h2>Eventos</h2>
        <div className="list">
          {view.executions.flatMap((item) => item.events).map((event) => (
            <div className="item" key={event.id}>
              <span>{event.type}</span>
              <span className="meta">{event.payload.message ?? event.at}</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
