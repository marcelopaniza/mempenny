// MemPenny — opencode nap scheduler.
//
// TS port of hooks/nap-check.sh. Listens for opencode's `session.created`
// event (delivered through the plugin API's single generic `event` hook —
// opencode never dispatches per-event-name keys, so the hook below MUST stay
// keyed `event`, not `"session.created"`) and, when a scheduled nap is due
// for the current project's memory dir, acts per the schedule's `mode`:
//
//   - "notify" (default): fire a desktop notification pointing the user at
//     /mempenny-clean --yes. Nothing runs without them.
//   - "auto" (explicit config opt-in, never written by /mempenny-nap itself):
//     start the cleanup by sending the `mempenny-clean` command into the new
//     session via `client.session.command` — a plain, non-experimental SDK
//     call that starts a turn on this session and never preempts a running
//     one. Falls back to notify if the invoke fails. The cleanup itself keeps
//     every safety rail (--yes skips only the confirm gate; backup-first).
//
// Defensive by design — a broken hook MUST NOT block session start: the whole
// handler is wrapped so any throw is swallowed (mirrors the bash `|| exit 0`).

import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs"
import { join } from "node:path"
import { createHash } from "node:crypto"
import { C1, configPath, dataDir, isSymlink, memoryDir, safeAbsPath } from "./_paths.ts"

type Frequency = "daily" | "weekly" | "once"

interface Schedule {
  frequency?: string
  time?: string
  mode?: string
}

interface MemPennyConfig {
  schedules?: Record<string, Schedule>
}

const FREQUENCIES: Frequency[] = ["daily", "weekly", "once"]
const TIME_RE = /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/

function localToday(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`
}

function localHhmm(): string {
  const d = new Date()
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
}

function sha1_12(s: string): string {
  return createHash("sha1").update(s).digest("hex").slice(0, 12)
}

// Port of the case statement in hooks/nap-check.sh. Returns true if a nap is
// due given the frequency, the last-fire date string, and today's date.
function isDue(frequency: Frequency, last: string, today: string): boolean {
  switch (frequency) {
    case "once":
      return last === ""
    case "daily":
      return last !== today
    case "weekly": {
      if (last === "") return true
      const lastEpoch = Date.parse(last) / 86_400_000
      const todayEpoch = Date.parse(today) / 86_400_000
      if (Number.isNaN(lastEpoch) || Number.isNaN(todayEpoch)) return true
      return todayEpoch - lastEpoch >= 7
    }
  }
}

export const MemPennyNap: Plugin = async ({ client, $, directory }) => {
  return {
    event: async ({ event }) => {
      try {
        if (event.type !== "session.created") return

        // Root project sessions only: a subagent/Task child session (parentID
        // set) must not re-trigger the nap check — mempenny's own clean spawns
        // subagents, and a nap firing inside its own cleanup would be absurd.
        const info = (
          event as { properties?: { info?: { id?: string; parentID?: string | null } } }
        ).properties?.info
        if (info?.parentID) return

        const projectDir = directory ?? process.cwd?.() ?? ""
        if (!projectDir) return

        const memDir = memoryDir(projectDir)
        if (!memDir) return // slug-derived path failed C1 — refuse to act.
        if (!existsSync(memDir) || isSymlink(memDir)) return // F-M2: never act on a symlinked memory dir.

        const cfg = configPath()
        if (!existsSync(cfg) || isSymlink(cfg)) return // F-M2: never read a symlinked config.
        if (!C1.test(cfg)) return

        let parsed: MemPennyConfig = {}
        try {
          parsed = JSON.parse(readFileSync(cfg, "utf8")) as MemPennyConfig
        } catch {
          return // malformed config: silent skip, same as the bash hook.
        }

        const schedule = parsed.schedules?.[memDir]
        const frequency = schedule?.frequency
        const time = schedule?.time
        if (!frequency || !time) return
        if (!FREQUENCIES.includes(frequency as Frequency)) return
        if (!TIME_RE.test(time)) return

        const data = dataDir()
        if (!safeAbsPath(data)) return
        if (!existsSync(data)) mkdirSync(data, { recursive: true, mode: 0o700 })

        const stateFile = join(data, `nap-${sha1_12(memDir)}.last`)
        if (!C1.test(stateFile)) return
        if (isSymlink(stateFile)) return // F-M2: refuse a poisoned state file.

        let last = ""
        if (existsSync(stateFile) && !isSymlink(stateFile)) {
          try {
            last = readFileSync(stateFile, "utf8").trim()
          } catch {
            last = ""
          }
        }

        const today = localToday()
        if (!isDue(frequency as Frequency, last, today)) return

        // Time gate: only fire at/after the scheduled HH:MM today (lexicographic).
        if (localHhmm() < time) return

        // All checks passed — record the fire BEFORE acting, so a notifier or
        // invoke failure can't cause a retry storm on the next session.
        try {
          writeFileSync(stateFile, today, { mode: 0o600 })
        } catch {
          return
        }

        // mode "auto" (explicit opt-in in the config): start the cleanup in
        // this new session. session.command resolves the mempenny-clean
        // command file and starts a turn; it never preempts a running one.
        let autoInvoked = false
        if (schedule?.mode === "auto" && info?.id) {
          try {
            await client.session.command({
              path: { id: info.id },
              body: { command: "mempenny-clean", arguments: "--yes" },
            })
            autoInvoked = true
          } catch {
            autoInvoked = false // fall through to the notify message below.
          }
        }

        const message = autoInvoked
          ? `nap: running /mempenny-clean --yes now (scheduled ${frequency} at ${time}). ` +
            `Backup-first; /mempenny-restore reverses any pass.`
          : `nap is due (scheduled ${frequency} at ${time}). ` +
            `Run /mempenny-clean --yes to tidy this project's memory. ` +
            `Backup-first; /mempenny-restore reverses any pass.`

        // Desktop notification. Bun's `$` parameterizes substitutions, so the
        // message is passed as a single arg (no shell injection). No-op on
        // platforms without a notifier — the log line below still records it.
        if (process.platform === "darwin") {
          await $`osascript -e ${`display notification "${message}" with title "MemPenny"`}`
        } else if (process.platform === "linux") {
          await $`notify-send ${"MemPenny"} ${message}`
        }

        await client.app.log({
          body: {
            service: "mempenny-nap",
            level: "info",
            message: `nap fired for ${sha1_12(memDir)} (${frequency}, ${
              autoInvoked ? "auto-invoked" : "notified"
            })`, // PENT-6: hash, not the path.
          },
        })
      } catch {
        // Swallow — a broken hook MUST NOT block session start.
      }
    },
  }
}
