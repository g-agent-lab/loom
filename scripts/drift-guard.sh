#!/bin/bash
# drift-guard.sh — guard against umputun-plugin drift / vendoring
# usage: drift-guard.sh [repo-root]
#
# Encodes the CLAUDE.md invariant that the only OWN plugins are
# autopilot, kit, slicer, and that every umputun plugin stays a
# `git-subdir` reference (never vendored under plugins/, never given a
# local "./plugins/..." source in the manifest).
#
# Two checks:
#   1. plugins/ contains EXACTLY the directories autopilot kit slicer
#      (any extra dir is a vendored upstream copy → fail).
#   2. no manifest entry uses a local "./plugins/..." source for a name
#      that is not one of the three own plugins (catches an umputun
#      entry rewritten to a local source).
#
# Exits 0 when clean; exits non-zero listing each offender. bash + jq only.

set -euo pipefail

root="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)}"
manifest="$root/.claude-plugin/marketplace.json"

own="autopilot kit slicer"

errors=0
err() {
    echo "drift-guard: $*" >&2
    errors=$((errors + 1))
}

if [ ! -d "$root/plugins" ]; then
    echo "drift-guard: plugins/ directory not found under $root" >&2
    exit 1
fi

# --- check 1: plugins/ holds exactly the three own plugins ---
for entry in "$root"/plugins/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    case " $own " in
        *" $name "*) ;;
        *) err "vendored/extra plugin dir not allowed: plugins/$name (own plugins are: $own)" ;;
    esac
done

# every own plugin dir must exist too
for name in $own; do
    [ -d "$root/plugins/$name" ] || err "missing own plugin dir: plugins/$name"
done

# --- check 2: only own plugins may use a local "./plugins/..." source ---
if [ ! -f "$manifest" ]; then
    echo "drift-guard: manifest not found: $manifest" >&2
    exit 1
fi
if ! jq empty "$manifest" 2>/dev/null; then
    echo "drift-guard: manifest is not valid JSON: $manifest" >&2
    exit 1
fi

# emit "name<TAB>source-string-or-empty" for every entry whose source is a string
while IFS=$'\t' read -r name src; do
    [ -n "$name" ] || continue
    case " $own " in
        *" $name "*) ;;  # own plugin with a local source — expected
        *) err "non-own plugin \"$name\" uses a local source \"$src\" — umputun plugins must stay git-subdir references" ;;
    esac
done < <(jq -r '.plugins[] | select((.source | type) == "string") | [.name, .source] | @tsv' "$manifest")

if [ "$errors" -gt 0 ]; then
    echo "drift-guard: $errors violation(s) found" >&2
    exit 1
fi

echo "drift-guard: OK (plugins/ == $own; no vendored umputun sources)"
