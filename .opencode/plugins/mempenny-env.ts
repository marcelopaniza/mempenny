// MemPenny — opencode env shim.
//
// Injects MemPenny's own, namespaced env vars into every shell execution so the
// command adapters and their bash blocks can resolve the plugin root and data
// dir without reading Claude Code's CLAUDE_* variables. We intentionally do NOT
// set CLAUDE_PROJECT_DIR / CLAUDE_PLUGIN_ROOT / CLAUDE_PLUGIN_DATA here: setting
// them from a non-Claude host risks colliding with a real Claude Code install
// sharing the machine (see PENT-1 in the v1.2 review). The command adapters
// instead instruct the model to substitute those references at read time.
//
// Docs: https://opencode.ai/docs/plugins/#inject-environment-variables

import type { Plugin } from "@opencode-ai/plugin"
import { dataDir, pluginRoot } from "./_paths.ts"

export const MemPennyEnv: Plugin = async () => {
  const root = pluginRoot()
  const data = dataDir()
  return {
    "shell.env": async (_input, output) => {
      output.env.MEMPENNY_HOST = "opencode"
      output.env.MEMPENNY_ROOT = root
      output.env.MEMPENNY_DATA_DIR = data
    },
  }
}
