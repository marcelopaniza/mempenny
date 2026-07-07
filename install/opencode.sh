#!/usr/bin/env bash
# MemPenny — opencode installer.
#
# Usage (from a clone of this repo):
#   ./install/opencode.sh            # global install for the current user
#   MEMPENNY_DATA_DIR=/opt/mempenny ./install/opencode.sh
#
# We deliberately do NOT support `curl | bash`. Clone the repo at a pinned tag
# and run this script from the checkout (see README) — review before running,
# matching the project's own SECURITY.md posture. (PENT-2.)
#
# What this does:
#   1. Copies the host-agnostic data tree (commands/, locales/, skills/,
#      .claude-plugin/, AGENTS.md, plus .opencode/) into $MEMPENNY_DATA_DIR as a
#      stable snapshot. Updates require re-running this installer — there is no
#      auto-update via `git pull`, so a compromised upstream cannot silently
#      change executed code.
#   2. Symlinks the opencode-discovery files into $OPENCODE_CONFIG_DIR so opencode
#      auto-loads them. The symlinks point at the stable snapshot in (1), not at
#      the clone, so they never follow a moving upstream.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${MEMPENNY_DATA_DIR:-$HOME/.local/share/mempenny}"
OC_ROOT="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

# F-M2 spirit: refuse to install over a symlinked data/config dir.
for d in "$DATA_DIR" "$OC_ROOT"; do
    if [ -L "$d" ]; then
        echo "error: $d is a symlink. Refusing (F-M2)." >&2
        exit 1
    fi
done

echo "Installing MemPenny for opencode"
echo "  repo:       $REPO_ROOT"
echo "  data dir:   $DATA_DIR"
echo "  opencode:   $OC_ROOT"
echo

# --- 1. Stable snapshot of the host-agnostic tree into DATA_DIR --------------
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"

for sub in commands locales skills .claude-plugin .opencode; do
    if [ -L "$DATA_DIR/$sub" ]; then
        echo "error: $DATA_DIR/$sub is a symlink. Refusing (F-M2)." >&2
        exit 1
    fi
    rm -rf "${DATA_DIR:?}/$sub"
    cp -a "$REPO_ROOT/$sub" "$DATA_DIR/$sub"
done
[ -f "$REPO_ROOT/AGENTS.md" ] && cp -a "$REPO_ROOT/AGENTS.md" "$DATA_DIR/AGENTS.md"

# Tighten perms (PENT-5): config-ish files 600, dirs 700.
find "$DATA_DIR" -type d -exec chmod 700 {} + 2>/dev/null || true
find "$DATA_DIR" -type f -name '*.json' -exec chmod 600 {} + 2>/dev/null || true

# --- 2. Symlink opencode-discovery files into OC_ROOT ------------------------
# Commands: all adapters.
mkdir -p "$OC_ROOT/commands"
for cmd in "$DATA_DIR"/.opencode/commands/*.md; do
    name=$(basename "$cmd")
    ln -sfn "$cmd" "$OC_ROOT/commands/$name"
done

# Plugins: only the real Plugin exports. _paths.ts is imported relatively by
# the others (Bun resolves the relative import through the symlink to DATA_DIR),
# so it is intentionally NOT symlinked into OC_ROOT — opencode would otherwise
# try to load it as a standalone plugin and it exports no Plugin function.
mkdir -p "$OC_ROOT/plugins"
for plug in mempenny-env.ts mempenny-nap.ts mempenny-apply.ts; do
    ln -sfn "$DATA_DIR/.opencode/plugins/$plug" "$OC_ROOT/plugins/$plug"
done

# Agent: the scoped mempenny agent (relaxed permissions for mempenny runs only).
mkdir -p "$OC_ROOT/agents"
ln -sfn "$DATA_DIR/.opencode/agents/mempenny.md" "$OC_ROOT/agents/mempenny.md"

echo "Done."
echo
echo "Restart opencode to load MemPenny."
echo "Commands: /mempenny-clean, /mempenny-nap, /mempenny-restore,"
echo "          /mempenny-memory-triage, /mempenny-memory-apply,"
echo "          /mempenny-memory-distill, /mempenny-memory-curate,"
echo "          /mempenny-memory-shard-roll"
echo
echo "If you also run Claude Code in this project, mempenny shares the same"
echo "memory dir + config (~/.claude/mempenny.config.json) automatically."
echo
echo "Uninstall: ./install/uninstall-opencode.sh"
