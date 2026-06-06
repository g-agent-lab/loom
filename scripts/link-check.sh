#!/bin/bash
# link-check.sh — assert relative markdown links resolve in-repo
# usage: link-check.sh [repo-root]
#
# Scans the public-facing markdown — root README.md, each plugin README.md,
# and everything under docs/ EXCEPT docs/plans/ (those cross-reference
# transient plan files) — and verifies every RELATIVE link target exists.
#
# Skips http(s):// and mailto: links and pure #anchor links. For links that
# carry a trailing #anchor or ?query, only the path part is resolved.
# Targets resolve relative to the directory of the file containing the link.
#
# Exits 0 when every relative link resolves; non-zero listing each dead link.
# bash + grep/sed only.

set -euo pipefail

root="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)}"

errors=0
err() {
    echo "link-check: $*" >&2
    errors=$((errors + 1))
}

# Build the file list: README.md, plugins/*/README.md, docs/**.md (no docs/plans/).
files=()
[ -f "$root/README.md" ] && files+=("$root/README.md")
while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
done < <(find "$root/plugins" -mindepth 2 -maxdepth 2 -name README.md 2>/dev/null | sort)
if [ -d "$root/docs" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] && files+=("$f")
    done < <(find "$root/docs" -type f -name '*.md' ! -path "$root/docs/plans/*" 2>/dev/null | sort)
fi

checked=0
for file in "${files[@]}"; do
    dir="$(dirname "$file")"
    # extract the URL part of every []() markdown link, one per line
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        case "$target" in
            http://*|https://*|mailto:*) continue ;;       # external
            \#*) continue ;;                                # pure anchor
        esac
        # strip a trailing #anchor or ?query — resolve only the path
        path="${target%%#*}"
        path="${path%%\?*}"
        [ -n "$path" ] || continue                          # was a pure anchor
        checked=$((checked + 1))
        # absolute (repo-rooted) vs relative-to-file resolution
        case "$path" in
            /*) resolved="$root$path" ;;
            *)  resolved="$dir/$path" ;;
        esac
        if [ ! -e "$resolved" ]; then
            rel="${file#"$root"/}"
            err "$rel: dead relative link \"$target\" → $resolved does not exist"
        fi
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\(//; s/\)$//')
done

if [ "$errors" -gt 0 ]; then
    echo "link-check: $errors dead link(s) found" >&2
    exit 1
fi

echo "link-check: OK ($checked relative link(s) across ${#files[@]} file(s))"
