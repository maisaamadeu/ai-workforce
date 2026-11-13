import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { api, type TaskSummary } from "../api";
import { complexityLabel, statusLabel, tagClass } from "../labels";

export function ProjectPage() {
  const { id = "" } = useParams();
  const navigate = useNavigate();
  const [project, setProject] = useState<{ id: string; name: string; path: string } | null>(null);
  const [tasks, setTasks] = useState<TaskSummary[]>([]);
  const [title, setTitle] = useState("");
  const [complexity, setComplexity] = useState("simple");
  const [relevant, setRelevant] = useState(false);
  const [destructive, setDestructive] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.project(id).then((view) => {
      setProject(view.project);
      setTasks(view.tasks);
    }).catch((reason: Error) => setError(reason.message));
  }, [id]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    try {
      const created = await api.createTask(id, { title, complexity, relevantOperation: relevant, destructive });
      navigate(`/tasks/${created.task.id}`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Falha ao criar tarefa.");
    }
  }

  if (!project) return <p className="meta">{error ?? "Carregando projeto."}</p>;

  return (
    <div className="stack">
      <div>
        <h1>{project.name}</h1>
        <p className="meta">{project.path}</p>
      </div>
      {error ? <p className="error">{error}</p> : null}
      <form className="panel stack" onSubmit={(event) => void submit(event)}>
        <h2>Nova tarefa</h2>
        <label className="field">Pedido<textarea value={title} onChange={(event) => setTitle(event.target.value)} /></label>
        <label className="field">
          Complexidade
          <select value={complexity} onChange={(event) => setComplexity(event.target.value)}>
            {Object.entries(complexityLabel).map(([value, text]) => <option key={value} value={value}>{text}</option>)}
          </select>
        </label>
        <label className="checks"><span><input type="checkbox" checked={relevant} onChange={(event) => setRelevant(event.target.checked)} /> Operação relevante</span></label>
        <label className="checks"><span><input type="checkbox" checked={destructive} onChange={(event) => setDestructive(event.target.checked)} /> Operação destrutiva</span></label>
        <button className="button primary" type="submit">Avaliar autorização</button>
      </form>
      <section className="panel">
        <h2>Histórico</h2>
        <div className="list">
          {tasks.map((task) => (
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
