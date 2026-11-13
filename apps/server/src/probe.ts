import { accessSync, constants } from "node:fs";
import { delimiter, join } from "node:path";
import { providerBinaries, type ProviderId } from "@ai-workforce/contracts";

export function binaryOnPath(name: string, pathEnv: string, platform = process.platform): boolean {
  const suffixes = platform === "win32" ? ["", ".exe", ".cmd"] : [""];
  for (const dir of pathEnv.split(delimiter)) {
    if (!dir) continue;
    for (const suffix of suffixes) {
      try {
        accessSync(join(dir, `${name}${suffix}`), constants.X_OK);
        return true;
      } catch {
        continue;
      }
    }
  }
  return false;
}

export function probeInstalledClis(pathEnv = process.env.PATH ?? ""): Record<ProviderId, boolean> {
  return {
    "claude-code": binaryOnPath(providerBinaries["claude-code"], pathEnv),
    codex: binaryOnPath(providerBinaries.codex, pathEnv),
    cursor: binaryOnPath(providerBinaries.cursor, pathEnv),
    copilot: binaryOnPath(providerBinaries.copilot, pathEnv),
  };
}
