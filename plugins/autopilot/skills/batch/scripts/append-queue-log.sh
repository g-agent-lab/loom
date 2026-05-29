#!/bin/bash
# append-queue-log.sh — append a timestamped line (or stdin) to the queue log
# usage: append-queue-log.sh <log-path> [message]
#
# if [message] is provided, append "<iso-ts>  <message>".
# if no [message] and stdin has data, append stdin verbatim (no timestamp prefix).
# this mirrors the planning plugin's append-progress.sh contract.

set -e

log="$1"
shift || true

if [ -z "$log" ]; then
    echo "error: usage: append-queue-log.sh <log-path> [message]" >&2
    exit 1
fi
if [ ! -f "$log" ]; then
    echo "error: log not initialized: $log" >&2
    exit 1
fi

if [ "$#" -gt 0 ]; then
    msg="$*"
    printf '%s  %s\n' "$(date -Iseconds)" "$msg" >> "$log"
else
    # passthrough stdin
    cat >> "$log"
fi
