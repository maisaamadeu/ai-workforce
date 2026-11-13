export { modelCatalog, modelsForProvider, resolveCatalog } from "./catalog.js";
export { detectMeteredEnv, sanitizeEnv } from "./env.js";
export { assertLocalOperator, decideResume, evaluateStart, OperatorError, pauseTeam } from "./manager.js";
export type { EvaluateInput, PauseTeamInput, PauseTeamResult, ResumeDecision, TeamExecution } from "./manager.js";
