#!/bin/bash
# validate-marketplace.sh — assert .claude-plugin/marketplace.json is well-formed
# usage: validate-marketplace.sh [repo-root]
#
# Validates the marketplace manifest against the repo invariants:
#   - top-level "name" and "owner" are present and non-empty
#   - every plugin entry has a unique "name" and a non-empty "description"
#   - own plugins (source is a string "./plugins/<x>") resolve to a directory
#     containing .claude-plugin/plugin.json whose "name" matches the manifest
#     entry and whose "version" is non-empty
#   - umputun entries (source is an object) are source.source == "git-subdir"
#     with a non-empty "url" and "path"
#
# Exits 0 when the manifest is clean; exits non-zero with one clear message
# per violation otherwise. Requires only bash + jq.

set -euo pipefail

root="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)}"
manifest="$root/.claude-plugin/marketplace.json"

errors=0
err() {
    echo "validate-marketplace: $*" >&2
    errors=$((errors + 1))
}

if [ ! -f "$manifest" ]; then
    echo "validate-marketplace: manifest not found: $manifest" >&2
    exit 1
fi

if ! jq empty "$manifest" 2>/dev/null; then
    echo "validate-marketplace: manifest is not valid JSON: $manifest" >&2
    exit 1
fi

# --- top-level fields ---
top_name=$(jq -r '.name // ""' "$manifest")
[ -n "$top_name" ] || err "top-level \"name\" is missing or empty"

owner_name=$(jq -r '.owner.name // ""' "$manifest")
[ -n "$owner_name" ] || err "top-level \"owner.name\" is missing or empty"

if [ "$(jq -r '.plugins | type' "$manifest")" != "array" ]; then
    err "\"plugins\" must be an array"
    echo "validate-marketplace: $errors error(s) found" >&2
    exit 1
fi

# --- duplicate name detection ---
dupes=$(jq -r '[.plugins[].name] | group_by(.) | map(select(length > 1) | .[0]) | .[]' "$manifest")
if [ -n "$dupes" ]; then
    while IFS= read -r d; do
        [ -n "$d" ] && err "duplicate plugin name: $d"
    done <<< "$dupes"
fi

# --- per-entry validation ---
count=$(jq '.plugins | length' "$manifest")
i=0
while [ "$i" -lt "$count" ]; do
    name=$(jq -r ".plugins[$i].name // \"\"" "$manifest")
    desc=$(jq -r ".plugins[$i].description // \"\"" "$manifest")
    src_type=$(jq -r ".plugins[$i].source | type" "$manifest")

    label="entry #$i"
    [ -n "$name" ] && label="plugin \"$name\""

    [ -n "$name" ] || err "$label: \"name\" is missing or empty"
    [ -n "$desc" ] || err "$label: \"description\" is missing or empty"

    if [ "$src_type" = "string" ]; then
        # own plugin — source is "./plugins/<x>"
        src=$(jq -r ".plugins[$i].source" "$manifest")
        case "$src" in
            ./plugins/*) ;;
            *) err "$label: own plugin source must be \"./plugins/<x>\", got \"$src\"" ;;
        esac
        plugin_json="$root/${src#./}/.claude-plugin/plugin.json"
        if [ ! -f "$plugin_json" ]; then
            err "$label: missing plugin manifest at ${src#./}/.claude-plugin/plugin.json"
        else
            pj_name=$(jq -r '.name // ""' "$plugin_json")
            pj_version=$(jq -r '.version // ""' "$plugin_json")
            if [ "$pj_name" != "$name" ]; then
                err "$label: plugin.json name \"$pj_name\" does not match manifest name \"$name\""
            fi
            [ -n "$pj_version" ] || err "$label: plugin.json \"version\" is missing or empty"
        fi
    elif [ "$src_type" = "object" ]; then
        # umputun entry — must be git-subdir with url + path
        ss=$(jq -r ".plugins[$i].source.source // \"\"" "$manifest")
        url=$(jq -r ".plugins[$i].source.url // \"\"" "$manifest")
        path=$(jq -r ".plugins[$i].source.path // \"\"" "$manifest")
        [ "$ss" = "git-subdir" ] || err "$label: object source must be \"git-subdir\", got \"$ss\""
        [ -n "$url" ] || err "$label: git-subdir source missing \"url\""
        [ -n "$path" ] || err "$label: git-subdir source missing \"path\""
    else
        err "$label: \"source\" must be a string (own) or object (git-subdir), got $src_type"
    fi

    i=$((i + 1))
done

if [ "$errors" -gt 0 ]; then
    echo "validate-marketplace: $errors error(s) found" >&2
    exit 1
fi

echo "validate-marketplace: OK ($count plugin entries)"
