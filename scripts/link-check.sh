#!/bin/bash
# link-check.sh — assert relative markdown links resolve in-repo
# usage: link-check.sh [repo-root]
#
# Scans the public-facing markdown — root README.md, root CHANGELOG.md, each
# plugin README.md, and everything under docs/ EXCEPT docs/plans/ (those
# cross-reference transient plan files) — and verifies every RELATIVE link
# target exists.
#
# Both inline links `[text](path)` and reference-style definitions
# `[id]: path` are extracted. Skips http(s):// and mailto: links and pure
# #anchor links. For links that carry a trailing #anchor or ?query, only the
# path part is resolved. Targets resolve relative to the directory of the file
# containing the link.
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

# extract_links FILE — print the URL part of every link in FILE, one per line.
# Handles two markdown link forms:
#   - inline      [text](url)   — the url may itself contain balanced ()
#                                 (the naive [^)]+ regex truncated those);
#                                 awk consumes the inner parens by depth. A
#                                 trailing markdown title — (url "title") or
#                                 (url 'title') — is dropped (URL ends at the
#                                 first unescaped whitespace inside the parens).
#   - reference   [id]: url     — link-reference definitions at line start.
# Code is skipped so a documented `](...)` is not mistaken for a link:
#   - fenced code blocks (``` or ~~~ ... fences) are ignored wholesale;
#   - inline code spans (`...`) are stripped from each line before scanning.
extract_links() {
    awk '
        # --- fenced code blocks: toggle on a fence line, skip while inside ---
        /^[[:space:]]*(```|~~~)/ { in_fence = !in_fence; next }
        in_fence { next }

        # --- strip inline code spans (`...`, ``...``, ...) from the line ---
        # Remove balanced backtick runs so any "](" inside code is not parsed.
        {
            line = $0
            out = ""
            n = length(line)
            i = 1
            while (i <= n) {
                c = substr(line, i, 1)
                if (c == "`") {
                    # measure the opening backtick run length
                    run = 0
                    while (i <= n && substr(line, i, 1) == "`") { run++; i++ }
                    # find a closing run of exactly the same length
                    closed = 0
                    while (i <= n) {
                        if (substr(line, i, 1) == "`") {
                            r2 = 0
                            j = i
                            while (j <= n && substr(line, j, 1) == "`") { r2++; j++ }
                            if (r2 == run) { i = j; closed = 1; break }
                            i = j   # different-length run: still inside the span
                        } else {
                            i++
                        }
                    }
                    if (!closed) break   # unterminated span: drop the rest
                } else {
                    out = out c
                    i++
                }
            }
            $0 = out
        }

        # reference-style definition: ^[id]: url  (optional "title" ignored)
        /^[[:space:]]*\[[^][]+\]:[[:space:]]*[^[:space:]]/ {
            ref = $0
            sub(/^[[:space:]]*\[[^][]+\]:[[:space:]]*/, "", ref)
            sub(/[[:space:]].*$/, "", ref)   # drop any trailing title
            if (ref != "") print ref
        }
        # inline links: scan for "](", then read the URL honoring nested parens.
        {
            s = $0
            while ((p = index(s, "](")) > 0) {
                s = substr(s, p + 2)          # text after the "]("
                depth = 1
                url = ""
                seen_url = 0                  # have we started the URL token?
                done_url = 0                  # has whitespace ended the URL?
                for (i = 1; i <= length(s); i++) {
                    c = substr(s, i, 1)
                    if (c == "(") { depth++; if (!done_url) { url = url c; seen_url = 1 } }
                    else if (c == ")") { depth--; if (depth == 0) break; if (!done_url) { url = url c } }
                    else if (c == " " || c == "\t") {
                        # first unescaped whitespace after the URL ends it
                        # (anything after is an optional "title"); skip leading
                        # whitespace before the URL token begins.
                        if (seen_url) done_url = 1
                    }
                    else if (!done_url) { url = url c; seen_url = 1 }
                }
                if (depth == 0 && url != "") print url
                s = substr(s, i + 1)          # continue past this link
            }
        }
    ' "$1"
}

# Build the file list: README.md, CHANGELOG.md, plugins/*/README.md,
# docs/**.md (no docs/plans/).
files=()
[ -f "$root/README.md" ] && files+=("$root/README.md")
[ -f "$root/CHANGELOG.md" ] && files+=("$root/CHANGELOG.md")
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
    done < <(extract_links "$file")
done

if [ "$errors" -gt 0 ]; then
    echo "link-check: $errors dead link(s) found" >&2
    exit 1
fi

echo "link-check: OK ($checked relative link(s) across ${#files[@]} file(s))"
