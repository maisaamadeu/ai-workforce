import { api, type Snapshot } from "../api";
import { billingLabel, unitLabel } from "../labels";

export function UsagePage({ snapshot, onChange }: { snapshot: Snapshot | null; onChange: () => void }) {
  async function enable(modelId: string, enabled: boolean) {
    await api.enableModel(modelId, enabled);
    onChange();
  }

  return (
    <div className="stack">
      <div>
        <h1>Uso e limites</h1>
        <p className="meta">Tokens, créditos, estimativa e quota ficam em linhas separadas. Valor ausente permanece como não medido.</p>
      </div>
      {snapshot?.integrations.map((integration) => (
        <section className="panel stack" key={integration.id}>
          <div className="row" style={{ justifyContent: "space-between" }}>
            <h2 style={{ margin: 0 }}>{integration.label}</h2>
            <span className="tag">{integration.availabilityLabel}</span>
          </div>
          <p className="meta">
            {integration.billingType ? billingLabel[integration.billingType] : "Tipo de cobrança não declarado"}
            {" · "}
            {integration.cliInstalled ? "CLI encontrado no PATH" : "CLI não encontrado no PATH"}
            {" · "}
            {integration.meteredAuthorized ? "Cobrança medida autorizada" : "API paga bloqueada"}
          </p>
          {integration.detectedApiKey ? (
            <p className="callout warn">Uma chave de API foi detectada no ambiente. O valor não é exibido e ela permanece bloqueada como alternativa.</p>
          ) : null}
          <table>
            <thead>
              <tr><th>Unidade</th><th>Valor</th></tr>
            </thead>
            <tbody>
              {integration.usage.map((meter) => (
                <tr key={meter.unit}>
                  <td>{unitLabel[meter.unit] ?? meter.unit}</td>
                  <td>{meter.amount === null ? "Não medido" : meter.amount}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      ))}
      <section className="panel stack">
        <h2>Modelos premium</h2>
        <p className="meta">Fable e modelos de terceiro do Cursor nascem desabilitados. Habilitar é uma decisão explícita e auditada.</p>
        <div className="row">
          <button className="button" type="button" onClick={() => void enable("claude-fable", true)}>Habilitar Fable</button>
          <button className="button" type="button" onClick={() => void enable("cursor-third-party", true)}>Habilitar modelo de terceiro</button>
        </div>
      </section>
      <section className="panel">
        <h2>Auditoria</h2>
        <table>
          <thead>
            <tr><th>Quando</th><th>Ação</th><th>Resultado</th><th>Detalhe</th></tr>
          </thead>
          <tbody>
            {snapshot?.audit.map((entry) => (
              <tr key={entry.id}>
                <td>{new Date(entry.at).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}</td>
                <td>{entry.action}</td>
                <td>{entry.result}{entry.limitApproved ? ` · ${entry.limitApproved}` : ""}</td>
                <td>{entry.detail}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
