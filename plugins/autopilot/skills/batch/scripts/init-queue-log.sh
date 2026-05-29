#!/bin/bash
# init-queue-log.sh — create a queue log file with a header
# usage: init-queue-log.sh <log-path> <plans-dir> <plan-count> <worktree-strategy>
#
# emits a single line to stdout in the form:
#   queue-log: <log-path>
# so the orchestrator can capture it via simple parse.

set -e

log="$1"
plans_dir="$2"
count="$3"
strategy="$4"

if [ -z "$log" ] || [ -z "$plans_dir" ] || [ -z "$count" ] || [ -z "$strategy" ]; then
    echo "error: usage: init-queue-log.sh <log-path> <plans-dir> <plan-count> <worktree-strategy>" >&2
    exit 1
fi

mkdir -p "$(dirname "$log")"
{
    echo "# cc-queue log"
    echo "started:  $(date -Iseconds)"
    echo "dir:      $plans_dir"
    echo "count:    $count"
    echo "strategy: $strategy"
    echo "------------------------------------------------------------"
} > "$log"

echo "queue-log: $log"
