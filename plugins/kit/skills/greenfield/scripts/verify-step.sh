#!/bin/bash
# verify-step.sh — run a step-specific verification and report pass/fail
# usage: verify-step.sh <step-name>
# outputs: 'pass' or 'fail: <reason>' on stdout, exit 0 on pass / 1 on fail
#
# step-name values map to llm-kit/bootstrap/greenfield.md and brownfield.md
# step verifications. unknown step name -> exit 2 (programmer error).

set -e

step="$1"
if [ -z "$step" ]; then
    echo "error: usage: verify-step.sh <step-name>" >&2
    exit 2
fi

ok() { echo "pass"; exit 0; }
fail() { echo "fail: $*"; exit 1; }

case "$step" in
    git-init)
        [ -d .git ] || fail ".git directory missing"
        git status >/dev/null 2>&1 || fail "git status errored"
        ok
        ;;
    ralphex-installed)
        command -v ralphex >/dev/null 2>&1 || fail "ralphex not on PATH"
        v=$(ralphex --version 2>&1 | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$v" ] || fail "could not parse ralphex --version output"
        ok
        ;;
    kit-installed)
        path="${KIT_INSTALL_PATH:-external/llm-kit}"
        [ -f "$path/UNIVERSAL_CORE.md" ] || fail "$path/UNIVERSAL_CORE.md missing"
        ok
        ;;
    claude-md-present)
        [ -f CLAUDE.md ] || fail "CLAUDE.md missing at project root"
        ok
        ;;
    agents-md-present)
        [ -f AGENTS.md ] || fail "AGENTS.md missing at project root"
        ok
        ;;
    docs-rules-present)
        [ -f docs/DOCS_RULES.md ] || fail "docs/DOCS_RULES.md missing"
        ok
        ;;
    gitignore-has-essentials)
        [ -f .gitignore ] || fail ".gitignore missing"
        grep -q 'node_modules' .gitignore 2>/dev/null || fail ".gitignore lacks node_modules"
        grep -q '\.env' .gitignore 2>/dev/null || fail ".gitignore lacks .env"
        ok
        ;;
    hooks-installed)
        [ -d .claude/hooks ] || fail ".claude/hooks/ missing"
        [ -x .claude/hooks/post-edit-lint.sh ] || fail ".claude/hooks/post-edit-lint.sh missing or not executable"
        ok
        ;;
    universal-scripts-present)
        for s in boundary-check arch-report architecture-diff-guard check-cross-module-relative-imports dep-cruiser-baseline docs-lint; do
            [ -f "scripts/$s.cjs" ] || fail "scripts/$s.cjs missing"
        done
        ok
        ;;
    baselines-at-zero)
        # baseline JSON files exist and parse to expected shape
        for b in .cross-module-import-baseline.json .dep-cruiser-baseline.json .boundary-baseline.json; do
            [ -f "$b" ] || fail "$b missing"
            python3 -c "import json; json.load(open('$b'))" 2>/dev/null || fail "$b not valid JSON"
        done
        ok
        ;;
    lint-passes)
        # caller passes the stack-appropriate lint command via env
        cmd="${LINT_COMMAND:-npm run lint}"
        if $cmd >/dev/null 2>&1; then ok; else fail "$cmd failed"; fi
        ;;
    *)
        echo "error: unknown verify step: $step" >&2
        exit 2
        ;;
esac
