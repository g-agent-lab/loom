#!/bin/bash
# version-sync.sh — enforce own-plugin version ↔ changelog consistency
# usage: version-sync.sh [BASE_REF]
#   BASE_REF may also be supplied via the $BASE environment variable.
#
# Two distinct, complementary responsibilities (see plan Technical Details):
#
#   1. STATIC consistency (always runs). For each own plugin the
#      plugin.json "version" must appear WITHIN that plugin's own changelog
#      SECTION — not just somewhere in the file. A bare grep is unsound:
#      "0.1.0" appears under BOTH `## autopilot` and `## kit` in the root
#      CHANGELOG, so a naive match cross-validates. autopilot/kit sections
#      are awk-extracted from root CHANGELOG.md (between `## <plugin>` and
#      the next `## ` header); slicer is checked in plugins/slicer/CHANGELOG.md.
#
#   2. DIFF-AWARE enforcement (only when a base ref resolves). This is what
#      actually encodes the "a change requires a bump" convention. If any
#      plugins/<own>/** file changed vs base, REQUIRE:
#        (a) HEAD plugin.json "version" is SEMVER-GREATER than at base
#            (unchanged FAILS, downgrade FAILS); AND
#        (b) that exact new version string is NEWLY ADDED to the plugin's OWN
#            changelog section — present in its section at HEAD AND absent from
#            that same section at BASE. Section-scoped (an added line under the
#            WRONG header in the shared root CHANGELOG does not count) AND
#            diff-aware (a stale version already in the section at BASE does not
#            count). A bump with no changelog line FAILS (not in HEAD section);
#            a changelog line with no bump FAILS via (a); a wrong-section add
#            FAILS (not in the correct HEAD section); a stale pre-existing
#            version FAILS (present in BASE section).
#      The guard keys off plugins/<x>/ paths ONLY — editing root
#      README/CLAUDE.md must NOT trip it.
#
#   $BASE resolution: explicit arg/env first; else `git merge-base
#   origin/master HEAD`. When no base resolves, fall back to static mode and
#   LOG that diff-aware enforcement was SKIPPED — never a silent pass.
#
# Exits 0 when clean; non-zero with a precise per-plugin message. bash + jq
# + awk + git only.

set -euo pipefail

# NOTE: signature asymmetry vs the other three check scripts — those take an
# optional [repo-root] as $1; here $1 is the BASE_REF (diff base), so the root is
# always derived from the script's own location, never an argument.
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)"
own="autopilot kit slicer"

errors=0
err() {
    echo "version-sync: $*" >&2
    errors=$((errors + 1))
}
log() {
    echo "version-sync: $*"
}

# Extract a plugin's changelog section from CHANGELOG text on STDIN: the lines
# from `## <plugin>` up to (but excluding) the next `## ` header. Reading stdin
# (not a path) lets BOTH the on-disk static check (`section "$hdr" < "$file"`)
# and the diff-aware HEAD check (`git show … | section "$hdr"`) share one impl.
#   $1 = section header name
section() {
    awk -v hdr="## $1" '
        $0 == hdr { capture = 1; next }
        capture && /^## / { exit }
        capture { print }
    '
}

plugin_version() {
    # version from a plugin.json on disk; $1 = plugin name
    jq -r '.version // ""' "$root/plugins/$1/.claude-plugin/plugin.json"
}

# SINGLE source of truth for where a plugin's changelog "section" lives.
#   - autopilot/kit share the root CHANGELOG under a `## <plugin>` header;
#     their section is awk-extracted to avoid cross-section false matches
#     (0.1.0 appears under both).
#   - slicer has its OWN dedicated changelog file; the entire file IS its
#     section, so the header is the empty sentinel "" (whole-file match).
# Two tiny accessors keep static + diff-aware modes in lockstep: the relpath is
# repo-RELATIVE (prefix "$root/" at the one site that needs an absolute path).
changelog_relpath() {
    case "$1" in
        slicer) echo "plugins/slicer/CHANGELOG.md" ;;
        *)      echo "CHANGELOG.md" ;;
    esac
}
changelog_header() {
    case "$1" in
        slicer) echo "" ;;
        *)      echo "$1" ;;
    esac
}

# literal (fixed-string) substring test, no regex surprises from dots
contains() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

# semver compare: returns 0 if $1 > $2 (strictly greater), else 1.
# Pure bash via sort -V; rejects equal.
semver_gt() {
    [ "$1" != "$2" ] || return 1
    local greatest
    greatest="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)"
    [ "$greatest" = "$1" ]
}

# ---------------------------------------------------------------------------
# 1. STATIC consistency (always)
# ---------------------------------------------------------------------------
for name in $own; do
    ver="$(plugin_version "$name")"
    if [ -z "$ver" ]; then
        err "$name: plugin.json \"version\" is missing or empty"
        continue
    fi
    file="$root/$(changelog_relpath "$name")"
    hdr="$(changelog_header "$name")"
    if [ ! -f "$file" ]; then
        err "$name: changelog not found: $file"
        continue
    fi
    if [ -n "$hdr" ]; then
        sec="$(section "$hdr" < "$file")"
        if [ -z "$sec" ]; then
            err "$name: changelog section \"## $hdr\" not found in $file"
            continue
        fi
        where="## $hdr in $(basename "$file")"
    else
        # dedicated changelog — whole file is the plugin's section
        sec="$(cat "$file")"
        where="$(basename "$file")"
    fi
    if ! contains "$ver" "$sec"; then
        err "$name: version $ver not found in its changelog section ($where)"
    fi
done

# ---------------------------------------------------------------------------
# 2. DIFF-AWARE enforcement (when a base ref resolves)
# ---------------------------------------------------------------------------
base="${1:-${BASE:-}}"
zero_sha="0000000000000000000000000000000000000000"

# treat an all-zero / empty / unresolvable SHA as "no base"
if [ -n "$base" ]; then
    if [ "$base" = "$zero_sha" ] || ! git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
        log "supplied BASE \"$base\" does not resolve to a commit — treating as no base"
        base=""
    fi
fi

# last-resort local fallback
if [ -z "$base" ]; then
    base="$(git -C "$root" merge-base origin/master HEAD 2>/dev/null || true)"
    if [ -n "$base" ]; then
        log "no BASE supplied; using local fallback merge-base origin/master HEAD = $base"
    fi
fi

if [ -z "$base" ]; then
    log "DIFF-AWARE enforcement SKIPPED — no base ref resolvable (ran static checks only)"
else
    # changed files vs base, restricted to plugins/<x>/ paths. The base already
    # passed `rev-parse --verify` above, so the only failure left is the diff /
    # merge-base path: with three-dot `base...HEAD`, unrelated histories or a
    # force-pushed base with no merge-base make `git diff` ERROR (exit 128).
    # A bare `|| true` would mask that failure as an empty set and SILENTLY
    # bypass enforcement, so distinguish FAILURE from "no changes": on failure,
    # log a visible SKIP (same never-a-silent-pass semantics as the no-base case)
    # and run static checks only.
    diff_status=0
    changed="$(git -C "$root" diff --name-only "$base"...HEAD -- 'plugins/' 2>/dev/null)" || diff_status=$?
    if [ "$diff_status" -ne 0 ]; then
        log "DIFF-AWARE enforcement SKIPPED — \`git diff $base...HEAD\` failed (no merge-base / unrelated history); ran static checks only"
        changed=""
    fi

    for name in $own; do
        # did any file under THIS plugin change? key off plugins/<x>/ ONLY.
        # NB: a here-string (no producer process) — a piped `printf … | grep -q`
        # can have printf killed by SIGPIPE once grep -q exits on the first
        # match; under `pipefail` that pipeline then reports non-zero, so `if !`
        # would wrongly treat a CHANGED plugin as UNCHANGED on large diffs.
        if ! grep -q "^plugins/$name/" <<<"$changed"; then
            continue
        fi

        head_ver="$(plugin_version "$name")"
        pj_path="plugins/$name/.claude-plugin/plugin.json"
        base_ver="$(git -C "$root" show "$base:$pj_path" 2>/dev/null | jq -r '.version // ""' 2>/dev/null || true)"

        if [ -z "$base_ver" ]; then
            # plugin.json absent at base (new plugin) — require a non-empty HEAD version
            if [ -z "$head_ver" ]; then
                err "$name: changed under plugins/$name/ but plugin.json has no version at HEAD"
                continue
            fi
            log "$name: new at base (no version to compare); requiring changelog entry for $head_ver"
        else
            # (a) HEAD version must be strictly semver-greater than base version
            if ! semver_gt "$head_ver" "$base_ver"; then
                if [ "$head_ver" = "$base_ver" ]; then
                    err "$name: plugins/$name/ changed but version is UNCHANGED ($head_ver) — a change requires a version bump"
                else
                    err "$name: plugins/$name/ changed but version went $base_ver → $head_ver (not semver-greater) — downgrade/non-bump not allowed"
                fi
                continue
            fi
        fi

        # (b) the exact NEW version string must be NEWLY ADDED to THIS plugin's
        #     OWN changelog section: present in the plugin's section at HEAD and
        #     NOT present in that same section at BASE. This is BOTH section-
        #     scoped (an added line under the WRONG header in the shared root
        #     CHANGELOG does not count) AND diff-aware (a version that was
        #     already sitting in the section at BASE — a stale pre-existing
        #     line — does not count). Reuses the stdin `section()` over
        #     `git show {BASE,HEAD}:<cl_path>`. For slicer (dedicated file,
        #     empty header) the whole file IS the section.
        cl_path="$(changelog_relpath "$name")"
        hdr="$(changelog_header "$name")"

        if [ -n "$hdr" ]; then
            head_sec="$(git -C "$root" show "HEAD:$cl_path" 2>/dev/null | section "$hdr" || true)"
            base_sec="$(git -C "$root" show "$base:$cl_path" 2>/dev/null | section "$hdr" || true)"
            sec_label="## $hdr in $cl_path"
        else
            head_sec="$(git -C "$root" show "HEAD:$cl_path" 2>/dev/null || true)"
            base_sec="$(git -C "$root" show "$base:$cl_path" 2>/dev/null || true)"
            sec_label="$cl_path"
        fi

        if ! contains "$head_ver" "$head_sec"; then
            err "$name: version bumped to $head_ver but it does not appear in the plugin's own changelog section ($sec_label) at HEAD"
            continue
        fi
        if contains "$head_ver" "$base_sec"; then
            err "$name: version bumped to $head_ver but \"$head_ver\" was already present in the plugin's changelog section ($sec_label) at BASE — no new entry was added for this bump"
            continue
        fi

        log "$name: bump $base_ver → $head_ver with matching changelog entry — OK"
    done
fi

if [ "$errors" -gt 0 ]; then
    echo "version-sync: $errors violation(s) found" >&2
    exit 1
fi

echo "version-sync: OK"
