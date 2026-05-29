#!/bin/bash
# detect-mode.sh — classify the current project as greenfield or brownfield
# usage: detect-mode.sh
# outputs one of: greenfield | brownfield
#
# logic (matches llm-kit/bootstrap/greenfield.md "Pre-flight check"):
#   greenfield = all of:
#     - no .git OR empty git log (no commits)
#     - no eslint / pyproject / ruff configs at root
#     - no CLAUDE.md at root
#   anything else = brownfield

set -e

is_greenfield=true

# 1. Git state
if [ -d .git ]; then
    if git log --oneline -1 >/dev/null 2>&1; then
        is_greenfield=false
    fi
fi

# 2. Linter configs at root
if ls eslint.config.* .eslintrc* pyproject.toml ruff.toml .flake8 go.mod 2>/dev/null | head -1 | grep -q .; then
    is_greenfield=false
fi

# 3. CLAUDE.md presence
if [ -f CLAUDE.md ]; then
    is_greenfield=false
fi

if [ "$is_greenfield" = true ]; then
    echo "greenfield"
else
    echo "brownfield"
fi
