#!/bin/bash
# resolve-file.sh — three-layer override chain for prompt / reference files
# usage: resolve-file.sh <relative-path> [data-dir]
#
# checks in order:
#   1. .claude/cc-kit/<path>           (project override)
#   2. <data-dir>/<path>               (user override; falls back to $CLAUDE_PLUGIN_DATA)
#   3. <skill-root>/references/<path>  (bundled default)
#
# outputs resolved content to stdout, errors out if not found.

set -e

path="$1"
if [ -z "$path" ]; then
    echo "error: usage: resolve-file.sh <relative-path> [data-dir]" >&2
    exit 1
fi

data_dir="${2:-$CLAUDE_PLUGIN_DATA}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f ".claude/cc-kit/$path" ]; then
    cat ".claude/cc-kit/$path"
elif [ -n "$data_dir" ] && [ -f "$data_dir/$path" ]; then
    cat "$data_dir/$path"
elif [ -f "$SKILL_ROOT/references/$path" ]; then
    cat "$SKILL_ROOT/references/$path"
else
    echo "error: file not found in override chain: $path" >&2
    exit 1
fi
