#!/bin/bash
# docs-lint.sh — assert the docs/ invariants from docs/DOCS_RULES.md
# usage: docs-lint.sh [repo-root]
#
# Enforces the machine-checkable subset of the llm-kit universal docs discipline
# (UNIVERSAL_CORE.md §5), tailored to this Markdown/shell/JSON marketplace:
#
#   1. The universal docs exist (CONTEXT, DOCS_RULES, SESSION, plans/ROADMAP).
#   2. Every all-caps env var that is READ but never ASSIGNED in any tracked
#      *.sh appears in docs/reference/env-variables.md (skips shell/system vars).
#   3. Every plan in docs/plans/active/ (not completed/) references a draft.
#   4. docs/SESSION.md is <=100 lines (warning, not a failure).
#
# Exits 0 when clean; non-zero listing each violation. bash + grep/awk/sed only.

set -euo pipefail

root="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)}"

errors=0
warns=0
err() {
    echo "docs-lint: $*" >&2
    errors=$((errors + 1))
}
warn() {
    echo "docs-lint: warning: $*" >&2
    warns=$((warns + 1))
}

# --- 1. required universal docs exist ---------------------------------------
for f in docs/CONTEXT.md docs/DOCS_RULES.md docs/SESSION.md docs/plans/ROADMAP.md; do
    [ -f "$root/$f" ] || err "missing required doc: $f"
done

# --- 2. env-var coverage -----------------------------------------------------
# All-caps shell/system vars that are never project configuration.
denylist='HOME|PATH|PWD|OLDPWD|IFS|SHELL|SHLVL|TERM|LANG|LC_ALL|USER|LOGNAME|HOSTNAME|TMPDIR|RANDOM|SECONDS|LINENO|REPLY|OPTARG|OPTIND|UID|EUID|PPID|FUNCNAME|BASHPID|BASH|BASH_SOURCE|BASH_REMATCH|BASH_VERSION|BASH_SUBSHELL|PIPESTATUS|OSTYPE|COLUMNS|LINES|GITHUB_ENV|GITHUB_OUTPUT|GITHUB_WORKSPACE'

envdoc="$root/docs/reference/env-variables.md"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$root" ls-files '*.sh' > "$tmp/shlist" 2>/dev/null || true

if [ ! -s "$tmp/shlist" ]; then
    warn "no tracked *.sh files found — skipping env-var coverage"
elif [ ! -f "$envdoc" ]; then
    err "missing docs/reference/env-variables.md (required for env-var coverage)"
else
    # Concatenate all script bodies once (assignment detection is repo-wide).
    : > "$tmp/allcontent"
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        cat "$root/$rel" >> "$tmp/allcontent"
        printf '\n' >> "$tmp/allcontent"
    done < "$tmp/shlist"

    # Referenced all-caps vars, minus the shell/system denylist. Strip comments
    # first (a var named only in a comment, e.g. a `$VAR` usage example, is not
    # actually read) — assignment detection below still scans the full content.
    sed 's/#.*$//' "$tmp/allcontent" > "$tmp/code"
    # shellcheck disable=SC2016  # the patterns are literal $ { } chars, not expansions
    grep -hoE '\$\{?[A-Z][A-Z0-9_]+\}?' "$tmp/code" \
        | tr -d '${}' | sort -u \
        | grep -vxE "$denylist" > "$tmp/referenced" || true

    is_assigned() {
        v="$1"
        if grep -qE "(^|[^A-Za-z0-9_])${v}=" "$tmp/allcontent"; then return 0; fi
        if grep -qE "[$]\{${v}:=" "$tmp/allcontent"; then return 0; fi
        if grep -qE "for[[:space:]]+${v}[[:space:]]+in" "$tmp/allcontent"; then return 0; fi
        if grep -qE "read[[:space:]].*${v}" "$tmp/allcontent"; then return 0; fi
        return 1
    }

    while IFS= read -r v; do
        [ -n "$v" ] || continue
        if is_assigned "$v"; then continue; fi
        if ! grep -qw "$v" "$envdoc"; then
            err "env var \$$v is read in a script but not documented in docs/reference/env-variables.md"
        fi
    done < "$tmp/referenced"
fi

# --- 3. plans in active/ reference a draft -----------------------------------
while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
        */completed/*) continue ;;
    esac
    case "$p" in
        *.md) ;;
        *) continue ;;
    esac
    if ! grep -qE 'drafts?/' "$root/$p"; then
        err "plan $p in plans/active/ does not reference a draft (see DOCS_RULES.md)"
    fi
done < <(git -C "$root" ls-files 'docs/plans/active/*' 2>/dev/null || true)

# --- 4. SESSION.md length (warn) ---------------------------------------------
if [ -f "$root/docs/SESSION.md" ]; then
    n="$(wc -l < "$root/docs/SESSION.md" | tr -d ' ')"
    if [ "$n" -gt 100 ]; then
        warn "docs/SESSION.md is $n lines (>100) — rotate older entries to changelog/YYYY-MM.md"
    fi
fi

# --- result ------------------------------------------------------------------
if [ "$errors" -gt 0 ]; then
    echo "docs-lint: FAILED ($errors error(s), $warns warning(s))" >&2
    exit 1
fi
echo "docs-lint: OK ($warns warning(s))"
