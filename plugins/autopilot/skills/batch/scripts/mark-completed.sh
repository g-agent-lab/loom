#!/bin/bash
# mark-completed.sh — move a successful plan into the completed subdirectory
# usage: mark-completed.sh <plan-path> [completed-subdir]
#
# default completed-subdir is "completed".
# creates the subdirectory lazily; idempotent if the plan already moved.
# refuses to overwrite an existing file in the target directory (errors out).

set -e

plan="$1"
sub="${2:-completed}"

if [ -z "$plan" ]; then
    echo "error: usage: mark-completed.sh <plan-path> [completed-subdir]" >&2
    exit 1
fi
if [ ! -f "$plan" ]; then
    echo "error: plan file not found: $plan" >&2
    exit 1
fi

dir=$(cd "$(dirname "$plan")" && pwd)
basename=$(basename "$plan")
target_dir="$dir/$sub"
target="$target_dir/$basename"

if [ -e "$target" ]; then
    echo "error: target already exists: $target (refusing to overwrite)" >&2
    exit 1
fi

mkdir -p "$target_dir"
mv "$plan" "$target"
echo "moved: $plan -> $target"
