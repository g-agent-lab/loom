#!/bin/bash
# resolve-rules.sh — load user-provided custom rules through override chain
# usage: resolve-rules.sh <filename> [data-dir]
#
# resolution chain (first non-empty wins):
#   1. .claude/<filename>          (project)
#   2. <data-dir>/<filename>       (user; falls back to $CLAUDE_PLUGIN_DATA)
#
# outputs file content or empty.

set -e

filename="$1"
if [ -z "$filename" ]; then
    echo "error: usage: resolve-rules.sh <filename> [data-dir]" >&2
    exit 1
fi

data_dir="${2:-$CLAUDE_PLUGIN_DATA}"

project_file=".claude/$filename"
user_file=""
[ -n "$data_dir" ] && user_file="$data_dir/$filename"

if [ -f "$project_file" ] && [ -s "$project_file" ]; then
    cat "$project_file"
elif [ -n "$user_file" ] && [ -f "$user_file" ] && [ -s "$user_file" ]; then
    cat "$user_file"
fi
