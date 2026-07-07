// MemPenny — shared path helpers for opencode plugins.
//
// Ports the path-safety guards from the Claude Code side (see SECURITY.md)
// into TypeScript so the nap plugin never trusts an unvalidated path:
//   - C1:   absolute-path regex  ^/[A-Za-z0-9/_.\ -]{1,4096}$
//   - F-M2: never read/write a symlink at a sensitive path
//   - slug: Claude Code's project-id encoding (sed 's|/|-|g; s|^-||')
//
// This module is imported by mempenny-env.ts and mempenny-nap.ts. It holds no
// secrets and performs no mutation — pure path resolution + validation.

import { existsSync, lstatSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"

// C1 — tight absolute-path regex, mirrors commands/clean.md + hooks/nap-check.sh.
export const C1 = /^\/[A-Za-z0-9/_.\ -]{1,4096}$/

// H1 — memory filename regex, used when a path's basename is load-bearing.
export const FILENAME_H1 = /^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$/

// Claude Code's project-id encoding: replace "/" with "-", strip leading "-".
export function slug(dir: string): string {
  return dir.replace(/\//g, "-").replace(/^-/, "")
}

// Resolve the MemPenny repo root by walking up to the directory that ships the
// Claude plugin manifest (`.claude-plugin/plugin.json`). This sentinel is stable
// whether the plugin is loaded from a checkout or copied into the config dir by
// install/opencode.sh. Falls back to ../../<plugins> if the sentinel is missing.
export function pluginRoot(): string {
  let dir = import.meta.dir
  for (let i = 0; i < 10; i++) {
    if (existsSync(join(dir, ".claude-plugin", "plugin.json"))) return dir
    const parent = dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  return join(import.meta.dir, "..", "..")
}

// C1-validated absolute path. Returns null if the path fails the regex — callers
// MUST treat null as "do not touch".
export function safeAbsPath(p: string | undefined): string | null {
  if (!p) return null
  return C1.test(p) ? p : null
}

// F-M2 — true if the path is a symlink. Used to refuse symlinked configs/state,
// mirroring the Claude side's TOCTOU guard.
export function isSymlink(p: string): boolean {
  try {
    return lstatSync(p).isSymbolicLink()
  } catch {
    return false
  }
}

// Memory dir for a project cwd, using the same slug rule as Claude Code. Returns
// null when the resolved path fails C1 — the caller must not act on null.
export function memoryDir(projectDir: string): string | null {
  if (!projectDir) return null
  const candidate = join(homedir(), ".claude", "projects", slug(projectDir), "memory")
  return C1.test(candidate) ? candidate : null
}

// Host-aware config path. Shares ~/.claude/mempenny.config.json when that dir
// exists (zero setup for users running both hosts); falls back to the opencode
// config dir otherwise. MEMPENNY_CONFIG_PATH wins outright (escape hatch).
export function configPath(): string {
  const override = safeAbsPath(process.env.MEMPENNY_CONFIG_PATH)
  if (override) return override
  const claudeDir = join(homedir(), ".claude")
  if (existsSync(claudeDir)) return join(claudeDir, "mempenny.config.json")
  return join(homedir(), ".config", "opencode", "mempenny.config.json")
}

// Plugin data dir (state files). XDG-ish; overridable via MEMPENNY_DATA_DIR.
export function dataDir(): string {
  const override = safeAbsPath(process.env.MEMPENNY_DATA_DIR)
  if (override) return override
  return join(homedir(), ".local", "share", "mempenny")
}
