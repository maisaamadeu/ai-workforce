import { Link } from "react-router-dom";
import { api, type Snapshot } from "../api";
import { categoryLabel } from "../labels";

export function ApprovalsPage({ snapshot, onChange }: { snapshot: Snapshot | null; onChange: () => void }) {
  async function update(category: string, mode: "automatic" | "require-approval" | "forbidden") {
    await api.setApprovalPolicy(category, mode);
    onChange();
  }

  return (
    <div className="stack">
      <div>
        <h1>Aprovações</h1>
        <p className="meta">A decisão fica no servidor. Um agente não consegue gravar estas políticas.</p>
      </div>
      <section className="panel">
        <h2>Pendentes</h2>
        <div className="list">
          {snapshot?.approvals.map((approval) => (
            <Link key={approval.id} to={`/tasks/${approval.taskId}`}>
              <span>{approval.prompt}</span>
              <span className="tag warn">Aguardando</span>
            </Link>
          ))}
          {snapshot && snapshot.approvals.length === 0 ? <p className="meta">Nenhuma autorização pendente.</p> : null}
        </div>
      </section>
      <section className="panel">
        <h2>Política por categoria</h2>
        <table>
          <thead><tr><th>Categoria</th><th>Modo</th></tr></thead>
          <tbody>
            {snapshot?.approvalPolicies.map((policy) => (
              <tr key={policy.category}>
                <td>{categoryLabel[policy.category] ?? policy.category}</td>
                <td>
                  <select value={policy.mode} onChange={(event) => void update(policy.category, event.target.value as typeof policy.mode)}>
                    <option value="automatic">Automática</option>
                    <option value="require-approval">Exige autorização</option>
                    <option value="forbidden">Proibida</option>
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
