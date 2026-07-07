// MemPenny — opencode apply helpers (custom tools).
//
// Collapses the deterministic, noisy bash scaffolding (backup creation + config
// load) into named tool calls so a clean run shows a couple of clean cards in
// the TUI instead of a wall of mkdir/cp/chmod/sha256sum/jq shell calls.
//
// SCOPE — only low-stakes, deterministic operations are ported:
//   - mempenny-backup       (mkdir + cp -a + chmod + SHA-256 manifest)
//   - mempenny-read-config  (host-aware path + F-M2 symlink guard + JSON parse)
//
// The hardened conservation check and the write/verify landing script are
// intentionally NOT ported — v1.1.4 fixed subtle bugs in their bash, and a TS
// re-port would re-open them. Those stay bash everywhere. This layer is an
// opencode-only optimization; the bash in commands/*.md remains the authoritative
// spec, and the command adapters fall back to it if a tool is unavailable.
//
// Non-breakage: this file lives under .opencode/, which is loaded ONLY by
// opencode. Claude Code, Codex, and every other host never execute it.

import { type Plugin, tool } from "@opencode-ai/plugin"
import { createHash } from "node:crypto"
import {
  chmodSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs"
import { join } from "node:path"
import { C1, configPath, isSymlink, safeAbsPath } from "./_paths.ts"

const FILENAME_H1 = /^[A-Za-z0-9][A-Za-z0-9_.\-]*\.md$/

// Local YYYYMMDDHHMMSS, matching the bash `date +%Y%m%d%H%M%S` used in clean.md.
function timestamp(): string {
  const d = new Date()
  const p = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}${p(d.getHours())}${p(
    d.getMinutes(),
  )}${p(d.getSeconds())}`
}

function sha256(path: string): string {
  return createHash("sha256").update(readFileSync(path)).digest("hex")
}

// Recursive chmod mirroring the bash L1 discipline: dirs 700, files 600.
function tighten(root: string): void {
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const p = join(root, entry.name)
    if (entry.isDirectory()) {
      chmodSync(p, 0o700)
      tighten(p)
    } else if (entry.isFile()) {
      chmodSync(p, 0o600)
    }
  }
}

interface BackupResult {
  ok: boolean
  backup_path?: string
  file_count?: number
  manifest?: { file: string; sha256: string }[]
  error?: string
}

export const MemPennyApply: Plugin = async () => {
  return {
    tool: {
      // Create a timestamped backup of a memory directory + return a SHA-256
      // manifest. Mirrors the bash backup block in commands/clean.md (mkdir -m
      // 700, cp -a, chmod 600 on files). Use this instead of running that bash
      // by hand — one verified operation instead of several shell calls.
      "mempenny-backup": tool({
        description:
          "Create a timestamped backup of a MemPenny memory directory and return a SHA-256 manifest of its .md files. Enforces the same path (C1) and symlink (F-M2) guards and permissions (dirs 700, files 600) as the bash backup in commands/clean.md. Use this on opencode instead of running the backup bash by hand.",
        args: {
          memory_dir: tool.schema.string(),
          backup_root: tool.schema.string(),
        },
        async execute(args): Promise<BackupResult> {
          const memDir = safeAbsPath(args.memory_dir)
          const backupRoot = safeAbsPath(args.backup_root)
          if (!memDir || !backupRoot) return { ok: false, error: "path fails C1 regex" }
          if (!existsSync(memDir)) return { ok: false, error: "memory_dir does not exist" }
          if (isSymlink(memDir)) return { ok: false, error: "memory_dir is a symlink (F-M2)" }
          if (isSymlink(backupRoot)) return { ok: false, error: "backup_root is a symlink (F-M2)" }

          try {
            mkdirSync(backupRoot, { recursive: true, mode: 0o700 })
            chmodSync(backupRoot, 0o700)
            const backupPath = join(backupRoot, `memory.backup-${timestamp()}-${process.pid}`)
            // cp -a equivalent: recursive, preserve timestamps, preserve symlinks
            // (dereference: false is the default — faithful replica of the source).
            cpSync(memDir, backupPath, { recursive: true, preserveTimestamps: true })
            tighten(backupPath)

            const manifest = readdirSync(backupPath)
              .filter((f) => f.endsWith(".md") && FILENAME_H1.test(f))
              .map((f) => ({ file: f, sha256: sha256(join(backupPath, f)) }))

            return { ok: true, backup_path: backupPath, file_count: manifest.length, manifest }
          } catch (e) {
            return { ok: false, error: String(e instanceof Error ? e.message : e) }
          }
        },
      }),

      // Load the MemPenny config from the host-aware path, refusing a symlink
      // (F-M2). Mirrors the config-load block in commands/clean.md. Returns the
      // parsed JSON so the command prompt can branch on its fields without a
      // separate jq shell call.
      "mempenny-read-config": tool({
        description:
          "Read and parse the MemPenny config from the host-aware path (MEMPENNY_CONFIG_PATH, else ~/.claude/mempenny.config.json if ~/.claude exists, else ~/.config/opencode/mempenny.config.json). Refuses a symlinked config (F-M2). Returns the parsed JSON, or {missing: true} if no config exists yet.",
        args: {},
        async execute(): Promise<{
          ok: boolean
          path?: string
          config?: unknown
          missing?: boolean
          error?: string
        }> {
          const cfg = configPath()
          if (!C1.test(cfg)) return { ok: false, error: "config path fails C1 regex" }
          if (!existsSync(cfg)) return { ok: true, missing: true, path: cfg }
          if (isSymlink(cfg)) return { ok: false, error: "config is a symlink (F-M2)", path: cfg }
          try {
            lstatSync(cfg) // re-stat to confirm a regular file after the symlink check
            const config = JSON.parse(readFileSync(cfg, "utf8"))
            return { ok: true, path: cfg, config }
          } catch (e) {
            return { ok: false, error: String(e instanceof Error ? e.message : e), path: cfg }
          }
        },
      }),
    },
  }
}
