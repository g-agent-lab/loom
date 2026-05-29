#!/bin/bash
# discover-plans.sh — list runnable plan files in lexicographic order
# usage: discover-plans.sh <plans-dir>
#
# outputs one absolute plan path per line, sorted ascii.
# a file is considered runnable when it has at least one
#   "### Task N:" or "### Iteration N:" heading at level 3 (regex anchored).
# files under a "completed/" subdirectory are excluded.
# non-md files are excluded.

set -e

dir="$1"
if [ -z "$dir" ]; then
    echo "error: usage: discover-plans.sh <plans-dir>" >&2
    exit 1
fi
if [ ! -d "$dir" ]; then
    echo "error: plans dir not found: $dir" >&2
    exit 1
fi

abs_dir=$(cd "$dir" && pwd)

# list .md files directly under <dir> (no recursion into subdirectories
# — this naturally excludes anything in completed/ and keeps the queue
# discovery deterministic and shallow).
while IFS= read -r f; do
    [ -z "$f" ] && continue
    # check it has at least one task heading
    if grep -qE '^###[[:space:]]+(Task|Iteration)[[:space:]]+[0-9]+:' "$f"; then
        echo "$f"
    fi
done < <(find "$abs_dir" -maxdepth 1 -type f -name '*.md' | sort)
