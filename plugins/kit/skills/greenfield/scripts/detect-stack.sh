#!/bin/bash
# detect-stack.sh — heuristic stack detection for the current project
# usage: detect-stack.sh
# outputs one of the supported stack identifiers, or 'unknown'
#
# supported identifiers (must match overlay filenames in llm-kit/overlays/):
#   typescript-nestjs
#   typescript-node-cli
#   python-fastapi      (future)
#   python-aiogram      (future)
#   go-stdlib           (future)
#   unknown
#
# precedence: explicit project signals beat package presence.

set -e

# python first (fastapi marker = explicit dependency)
if [ -f pyproject.toml ] && grep -qiE 'fastapi|uvicorn' pyproject.toml 2>/dev/null; then
    echo "python-fastapi"; exit 0
fi
if [ -f pyproject.toml ] && grep -qiE 'aiogram' pyproject.toml 2>/dev/null; then
    echo "python-aiogram"; exit 0
fi

# go module
if [ -f go.mod ]; then
    echo "go-stdlib"; exit 0
fi

# typescript node CLI vs NestJS — distinguish by presence of nestjs deps
if [ -f package.json ]; then
    if grep -qiE '"@nestjs/' package.json 2>/dev/null; then
        echo "typescript-nestjs"; exit 0
    fi
    if grep -qiE '"commander"|"execa"|"@iarna/toml"' package.json 2>/dev/null; then
        echo "typescript-node-cli"; exit 0
    fi
    # generic node — fall through to ask
fi

echo "unknown"
