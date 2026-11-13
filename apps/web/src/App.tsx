import { createContext, useEffect, useState } from "react";
import { NavLink, Route, Routes } from "react-router-dom";
import { api, type Snapshot } from "./api";
import { modeCopy } from "./labels";
import { ApprovalsPage } from "./pages/ApprovalsPage";
import { DashboardPage } from "./pages/DashboardPage";
import { ProjectPage } from "./pages/ProjectPage";
import { TaskPage } from "./pages/TaskPage";
import { UsagePage } from "./pages/UsagePage";
import { WorkspacePage } from "./pages/WorkspacePage";

export const RefreshContext = createContext(0);

export function App() {
  const [tick, setTick] = useState(0);
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const theme = document.documentElement.dataset.theme === "dark" ? "dark" : "light";

  useEffect(() => {
    const socket = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/api/events`);
    socket.onmessage = () => setTick((value) => value + 1);
    return () => socket.close();
  }, []);

  useEffect(() => {
    api.snapshot().then(setSnapshot).catch((reason: Error) => setError(reason.message));
  }, [tick]);

  async function setMode(mode: Snapshot["organization"]["mode"]) {
    await api.setMode(mode);
    setTick((value) => value + 1);
  }

  function toggleTheme() {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    localStorage.setItem("ai-workforce-theme", next);
    setTick((value) => value + 1);
  }

  return (
    <RefreshContext.Provider value={tick}>
      <div className="app">
        <aside className="sidebar">
          <div className="brand">
            <strong>AI Workforce</strong>
            <span>Operação local</span>
          </div>
          <nav className="nav">
            <NavLink to="/" end>Painel</NavLink>
            <NavLink to="/usage">Uso e limites</NavLink>
            <NavLink to="/approvals">Aprovações{snapshot?.approvals.length ? ` (${snapshot.approvals.length})` : ""}</NavLink>
          </nav>
          <div className="spacer">
            <button className="text-button" type="button" onClick={toggleTheme}>
              Tema {theme === "dark" ? "escuro" : "claro"}
            </button>
          </div>
        </aside>
        <main className="main">
          <header className="topbar">
            <div className="stack">
              <div className="mode" role="group" aria-label="Modo global">
                {(["economic", "balanced", "restricted"] as const).map((mode) => (
                  <button key={mode} type="button" aria-pressed={snapshot?.organization.mode === mode} onClick={() => void setMode(mode)}>
                    {mode === "economic" ? "Econômico" : mode === "balanced" ? "Equilibrado" : "Restrito"}
                  </button>
                ))}
              </div>
              <p className="meta">{snapshot ? modeCopy[snapshot.organization.mode] : "Carregando a organização local."}</p>
            </div>
          </header>
          {error ? <p className="error">{error}</p> : null}
          <Routes>
            <Route path="/" element={<DashboardPage snapshot={snapshot} onChange={() => setTick((value) => value + 1)} />} />
            <Route path="/usage" element={<UsagePage snapshot={snapshot} onChange={() => setTick((value) => value + 1)} />} />
            <Route path="/approvals" element={<ApprovalsPage snapshot={snapshot} onChange={() => setTick((value) => value + 1)} />} />
            <Route path="/workspaces/:id" element={<WorkspacePage onChange={() => setTick((value) => value + 1)} />} />
            <Route path="/projects/:id" element={<ProjectPage />} />
            <Route path="/tasks/:id" element={<TaskPage onChange={() => setTick((value) => value + 1)} />} />
          </Routes>
        </main>
      </div>
    </RefreshContext.Provider>
  );
}
