#!/usr/bin/env bash
# MemPenny — opencode uninstaller.
#
# Reverses install/opencode.sh. Removes only the files that installer created
# (the mempenny-* symlinks in OC_ROOT, and the DATA_DIR snapshot). Never touches
# unrelated user files.

set -euo pipefail

DATA_DIR="${MEMPENNY_DATA_DIR:-$HOME/.local/share/mempenny}"
OC_ROOT="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

echo "Uninstalling MemPenny for opencode"
echo "  data dir:   $DATA_DIR"
echo "  opencode:   $OC_ROOT"
echo

# 1. Remove only our command + plugin symlinks. We delete by basename, and only
#    if the target is inside DATA_DIR (so a user's same-named file is never hit).
for name in \
    mempenny-clean.md mempenny-nap.md mempenny-restore.md \
    mempenny-memory-triage.md mempenny-memory-apply.md \
    mempenny-memory-distill.md mempenny-memory-curate.md \
    mempenny-memory-shard-roll.md; do
    link="$OC_ROOT/commands/$name"
    if [ -L "$link" ]; then
        case "$(readlink "$link")" in
            "$DATA_DIR"/*) rm -f "$link" ;;
            *) echo "skip (not ours): $link -> $(readlink "$link")" ;;
        esac
    fi
done

for name in mempenny-env.ts mempenny-nap.ts mempenny-apply.ts; do
    link="$OC_ROOT/plugins/$name"
    if [ -L "$link" ]; then
        case "$(readlink "$link")" in
            "$DATA_DIR"/*) rm -f "$link" ;;
            *) echo "skip (not ours): $link -> $(readlink "$link")" ;;
        esac
    fi
done

# The scoped mempenny agent.
link="$OC_ROOT/agents/mempenny.md"
if [ -L "$link" ]; then
    case "$(readlink "$link")" in
        "$DATA_DIR"/*) rm -f "$link" ;;
        *) echo "skip (not ours): $link -> $(readlink "$link")" ;;
    esac
fi

# 2. Remove the DATA_DIR snapshot. Refuse if it's a symlink (F-M2).
if [ -e "$DATA_DIR" ]; then
    if [ -L "$DATA_DIR" ]; then
        echo "error: $DATA_DIR is a symlink; leaving it in place (F-M2). Remove manually." >&2
        exit 1
    fi
    rm -rf "${DATA_DIR:?}"
fi

echo "Done. The shared ~/.claude/mempenny.config.json (if any) is left untouched."
echo "Restart opencode to clear MemPenny from this session."
