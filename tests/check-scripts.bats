#!/usr/bin/env bats
# SUT: scripts/{validate-marketplace,drift-guard,version-sync,link-check}.sh
#
# These are the FAIL-path tests for the four marketplace check scripts. CI only
# ever runs each script against the live (passing) repo; without these, a guard
# silently refactored into a no-op (early `exit 0`, a broken grep, an empty awk
# section) would keep CI green — false confidence. Each test here builds a
# deliberately broken fixture per invariant and asserts the script exits
# non-zero with the expected message.
#
# Two fixture styles:
#   - validate-marketplace / drift-guard / link-check accept a `[repo-root]`
#     argument, so a broken fixture DIR is enough (no git needed).
#   - version-sync resolves its root from the SCRIPT's own location
#     (`dirname "$0"` -> git toplevel) and keys off git history, so its fixtures
#     are throwaway git repos with version-sync.sh COPIED in — invoking that
#     copy makes the script see the fixture repo as its root.

load helpers

setup() {
    make_tmpdir
}

teardown() {
    cleanup_tmpdir
}

# ---------------------------------------------------------------------------
# helpers for arg-style scripts (validate-marketplace, drift-guard, link-check)
# ---------------------------------------------------------------------------

# write_manifest ROOT < json — write a marketplace.json under ROOT.
write_manifest() {
    mkdir -p "$1/.claude-plugin"
    cat > "$1/.claude-plugin/marketplace.json"
}

# make_own_plugin ROOT NAME VERSION [PLUGIN_JSON_NAME]
# create plugins/NAME/.claude-plugin/plugin.json on disk.
make_own_plugin() {
    local root="$1" name="$2" version="$3" pjname="${4:-$2}"
    mkdir -p "$root/plugins/$name/.claude-plugin"
    cat > "$root/plugins/$name/.claude-plugin/plugin.json" <<EOF
{ "name": "$pjname", "version": "$version" }
EOF
}

# ---------------------------------------------------------------------------
# helpers for version-sync (throwaway git repo with the script copied in)
# ---------------------------------------------------------------------------

# vs_init ROOT — make ROOT a git repo with version-sync.sh copied to scripts/.
vs_init() {
    local root="$1"
    mkdir -p "$root/scripts"
    cp "$SUT_VERSYNC" "$root/scripts/version-sync.sh"
    chmod +x "$root/scripts/version-sync.sh"
    git -C "$root" init -q
    git -C "$root" config user.email t@t.t
    git -C "$root" config user.name t
}

# vs_commit ROOT MSG — stage everything and commit.
vs_commit() {
    git -C "$1" add -A
    git -C "$1" commit -qm "$2"
}

# run the COPIED version-sync.sh so its root resolves to the fixture repo.
run_versync() {
    local root="$1"; shift
    run bash -c "cd '$root' && './scripts/version-sync.sh' \"\$@\"" _ "$@"
}

# ===========================================================================
# drift-guard.sh — a vendored upstream plugin dir is rejected
# ===========================================================================

@test "drift-guard: a vendored plugins/brainstorm/ dir FAILS" {
    R="${TMP}/drift"
    # the three legit own plugins...
    for p in autopilot kit slicer; do mkdir -p "$R/plugins/$p"; done
    # ...plus an illicit vendored upstream copy
    mkdir -p "$R/plugins/brainstorm"
    write_manifest "$R" <<'EOF'
{ "name": "loom", "owner": { "name": "x" }, "plugins": [
  { "name": "autopilot", "source": "./plugins/autopilot", "description": "d" },
  { "name": "kit", "source": "./plugins/kit", "description": "d" },
  { "name": "slicer", "source": "./plugins/slicer", "description": "d" }
] }
EOF
    run "$SUT_DRIFT" "$R"
    [ "$status" -ne 0 ]
    # grep -qF (a simple command) is bats-ENFORCED: a non-zero exit aborts the
    # test. `[[ ... ]]` compound conditionals are NOT — bats only fails on the
    # test's final line for those — so message specificity must use grep.
    echo "$output" | grep -qF "plugins/brainstorm"
    echo "$output" | grep -qF "vendored"
}

# ===========================================================================
# validate-marketplace.sh — own-plugin invariants
# ===========================================================================

@test "validate-marketplace: own plugin missing version FAILS" {
    R="${TMP}/vm-noversion"
    make_own_plugin "$R" autopilot ""   # empty version
    make_own_plugin "$R" kit 0.1.0
    make_own_plugin "$R" slicer 0.1.0
    write_manifest "$R" <<'EOF'
{ "name": "loom", "owner": { "name": "x" }, "plugins": [
  { "name": "autopilot", "source": "./plugins/autopilot", "description": "d" },
  { "name": "kit", "source": "./plugins/kit", "description": "d" },
  { "name": "slicer", "source": "./plugins/slicer", "description": "d" }
] }
EOF
    run "$SUT_VALIDATE" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "version"
    echo "$output" | grep -qF "autopilot"
}

@test "validate-marketplace: plugin.json name mismatch FAILS" {
    R="${TMP}/vm-mismatch"
    # plugin.json says "wrong-name" but the manifest entry is "autopilot"
    make_own_plugin "$R" autopilot 0.1.0 wrong-name
    make_own_plugin "$R" kit 0.1.0
    make_own_plugin "$R" slicer 0.1.0
    write_manifest "$R" <<'EOF'
{ "name": "loom", "owner": { "name": "x" }, "plugins": [
  { "name": "autopilot", "source": "./plugins/autopilot", "description": "d" },
  { "name": "kit", "source": "./plugins/kit", "description": "d" },
  { "name": "slicer", "source": "./plugins/slicer", "description": "d" }
] }
EOF
    run "$SUT_VALIDATE" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "does not match"
    echo "$output" | grep -qF "wrong-name"
}

# ===========================================================================
# link-check.sh — a dead relative link is reported
# ===========================================================================

@test "link-check: a dead relative link FAILS" {
    R="${TMP}/lc"
    mkdir -p "$R"
    printf '# t\n\n[broken](./does-not-exist.md)\n' > "$R/README.md"
    run "$SUT_LINKCHECK" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "dead relative link"
    echo "$output" | grep -qF "does-not-exist.md"
}

@test "link-check: a TITLED inline link to an existing file PASSES" {
    # Regression: a standard titled link `[text](path "Title")` must extract
    # only `path`, not `path "Title"` — otherwise it never resolves and trips a
    # false dead-link. Both double- and single-quoted titles, plus a title on a
    # link carrying a #anchor, must all resolve to the real target.
    R="${TMP}/lc-title"
    mkdir -p "$R/docs"
    printf '# target\n' > "$R/docs/real.md"
    {
        printf '# t\n\n'
        printf '[dq](docs/real.md "Some Title")\n'
        printf "[sq](docs/real.md 'Other Title')\n"
        printf '[anchor](docs/real.md#section "T")\n'
    } > "$R/README.md"
    run "$SUT_LINKCHECK" "$R"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "OK"
}

@test "link-check: a dead link inside code (span/fence) is NOT reported" {
    # Regression: a `](nonexistent)` inside an inline code span or a fenced code
    # block is documentation, not a link — it must not trip a false dead-link.
    R="${TMP}/lc-code"
    mkdir -p "$R"
    {
        printf '# t\n\n'
        printf 'Inline: use `[x](./ghost.md)` syntax for links.\n\n'
        printf '```\n'
        printf '[y](./phantom.md)\n'
        printf '```\n\n'
        printf '~~~markdown\n'
        printf '[z](./vapor.md)\n'
        printf '~~~\n'
    } > "$R/README.md"
    run "$SUT_LINKCHECK" "$R"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "OK"
}

@test "link-check: a real dead link still FAILS even amid code/titled links" {
    # Regression guard: the code/title leniency must NOT swallow a genuine dead
    # relative link sitting in the same file as a code span and a titled link.
    R="${TMP}/lc-mixed"
    mkdir -p "$R/docs"
    printf '# target\n' > "$R/docs/real.md"
    {
        printf '# t\n\n'
        printf '[ok](docs/real.md "Title")\n'
        printf 'code: `[c](./fake.md)`\n'
        printf '[bad](./genuinely-dead.md)\n'
    } > "$R/README.md"
    run "$SUT_LINKCHECK" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "dead relative link"
    echo "$output" | grep -qF "genuinely-dead.md"
    # the code-span and titled targets must NOT appear as dead links. A negated
    # pipeline (`! ... | grep`) is NOT bats-enforced (the `!` suppresses the
    # abort); a single-bracket equality on a substring-stripped copy IS — it
    # fails iff the substring is present.
    [ "$output" = "${output/fake.md/}" ]
    [ "$output" = "${output/Title/}" ]
}

# ===========================================================================
# version-sync.sh — STATIC section-scoped matching
# ===========================================================================

@test "version-sync STATIC: kit version present only under autopilot's section FAILS" {
    # kit's plugin.json version (0.9.9) appears in the root CHANGELOG, but ONLY
    # inside the `## autopilot` section — NOT under `## kit`. A naive whole-file
    # grep would cross-validate; section-scoping must reject it.
    R="${TMP}/vs-static"
    vs_init "$R"
    for p in autopilot kit slicer; do
        mkdir -p "$R/plugins/$p/.claude-plugin"
    done
    printf '{ "name": "autopilot", "version": "0.1.0" }\n' > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    printf '{ "name": "kit", "version": "0.9.9" }\n'       > "$R/plugins/kit/.claude-plugin/plugin.json"
    printf '{ "name": "slicer", "version": "0.1.0" }\n'    > "$R/plugins/slicer/.claude-plugin/plugin.json"
    # slicer dedicated changelog (whole-file section)
    printf '# slicer\n\n### 0.1.0\n- init\n' > "$R/plugins/slicer/CHANGELOG.md"
    # root CHANGELOG: kit's 0.9.9 sits under ## autopilot, NOT under ## kit
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.1.0
- init
- (a stray mention of kit 0.9.9 here, in the WRONG section)

## kit

### 0.1.0
- init
EOF
    run_versync "$R"          # no base -> static mode only
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "kit"
    echo "$output" | grep -qF "0.9.9"
}

# ===========================================================================
# version-sync.sh — DIFF-AWARE enforcement (built in a throwaway git repo)
# ===========================================================================

# Build a baseline fixture repo: all three own plugins at 0.1.0 with matching
# changelog sections, committed. Echoes the base SHA. Caller then mutates and
# commits a HEAD, then runs version-sync with that base.
vs_baseline() {
    local R="$1"
    vs_init "$R"
    for p in autopilot kit slicer; do
        mkdir -p "$R/plugins/$p/.claude-plugin"
        printf '{ "name": "%s", "version": "0.1.0" }\n' "$p" \
            > "$R/plugins/$p/.claude-plugin/plugin.json"
    done
    printf '# slicer\n\n### 0.1.0\n- init\n' > "$R/plugins/slicer/CHANGELOG.md"
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.1.0
- init

## kit

### 0.1.0
- init
EOF
    vs_commit "$R" base
    git -C "$R" rev-parse HEAD
}

@test "version-sync DIFF: plugin changed but version UNCHANGED FAILS" {
    R="${TMP}/vs-unchanged"
    base="$(vs_baseline "$R")"
    # touch a file under plugins/autopilot/ WITHOUT bumping the version
    mkdir -p "$R/plugins/autopilot/skills"
    printf 'tweak\n' > "$R/plugins/autopilot/skills/x.md"
    vs_commit "$R" "edit autopilot, no bump"
    run_versync "$R" "$base"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "UNCHANGED"
    echo "$output" | grep -qF "autopilot"
}

@test "version-sync DIFF: bump with NO changelog line FAILS" {
    R="${TMP}/vs-nochangelog"
    base="$(vs_baseline "$R")"
    # bump the version but add no matching changelog entry
    printf '{ "name": "autopilot", "version": "0.2.0" }\n' \
        > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    vs_commit "$R" "bump autopilot, no changelog"
    run_versync "$R" "$base"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "autopilot"
    echo "$output" | grep -qF "0.2.0"
}

@test "version-sync DIFF: a DOWNGRADE FAILS" {
    R="${TMP}/vs-downgrade"
    # baseline starts autopilot at 0.2.0 so we can downgrade it
    vs_init "$R"
    for p in autopilot kit slicer; do
        mkdir -p "$R/plugins/$p/.claude-plugin"
    done
    printf '{ "name": "autopilot", "version": "0.2.0" }\n' > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    printf '{ "name": "kit", "version": "0.1.0" }\n'       > "$R/plugins/kit/.claude-plugin/plugin.json"
    printf '{ "name": "slicer", "version": "0.1.0" }\n'    > "$R/plugins/slicer/.claude-plugin/plugin.json"
    printf '# slicer\n\n### 0.1.0\n- init\n' > "$R/plugins/slicer/CHANGELOG.md"
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.2.0
- init

## kit

### 0.1.0
- init
EOF
    vs_commit "$R" base
    base="$(git -C "$R" rev-parse HEAD)"
    # downgrade 0.2.0 -> 0.1.0
    printf '{ "name": "autopilot", "version": "0.1.0" }\n' \
        > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    vs_commit "$R" "downgrade autopilot"
    run_versync "$R" "$base"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "autopilot"
    echo "$output" | grep -qF "0.1.0"
}

@test "version-sync DIFF: bump + matching changelog line PASSES (positive control)" {
    R="${TMP}/vs-ok"
    base="$(vs_baseline "$R")"
    # bump version AND add a changelog entry under the ## autopilot section
    printf '{ "name": "autopilot", "version": "0.2.0" }\n' \
        > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.2.0
- a real new entry

### 0.1.0
- init

## kit

### 0.1.0
- init
EOF
    vs_commit "$R" "bump autopilot + changelog"
    run_versync "$R" "$base"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "OK"
}

@test "version-sync DIFF: bump whose new line lands in the WRONG section FAILS" {
    # Regression for the section-scoped + diff-aware check. autopilot is bumped
    # 0.1.0 -> 0.2.0, but the only NEW changelog line mentioning 0.2.0 is added
    # under ## kit (the wrong section). Crucially, autopilot's OWN section
    # ALREADY contained a stale "0.2.0" line at BASE, so the old belt-and-
    # suspenders HEAD-section check would wrongly pass and the old global
    # added-line scan would also pass (0.2.0 IS in an added line — under kit).
    # The correct check (newly-added to THIS plugin's section: in HEAD section
    # AND NOT in BASE section) must reject it: 0.2.0 was already in the section
    # at BASE, so it was not newly added for this bump.
    R="${TMP}/vs-wrongsec"
    vs_init "$R"
    for p in autopilot kit slicer; do
        mkdir -p "$R/plugins/$p/.claude-plugin"
    done
    # autopilot.json starts at 0.1.0 but its section already carries a stale 0.2.0
    printf '{ "name": "autopilot", "version": "0.1.0" }\n' > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    printf '{ "name": "kit", "version": "0.1.0" }\n'       > "$R/plugins/kit/.claude-plugin/plugin.json"
    printf '{ "name": "slicer", "version": "0.1.0" }\n'    > "$R/plugins/slicer/.claude-plugin/plugin.json"
    printf '# slicer\n\n### 0.1.0\n- init\n' > "$R/plugins/slicer/CHANGELOG.md"
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.2.0
- STALE: this 0.2.0 line already existed at BASE in the correct section

### 0.1.0
- init

## kit

### 0.1.0
- init
EOF
    vs_commit "$R" base
    base="$(git -C "$R" rev-parse HEAD)"
    # bump autopilot to 0.2.0; the ONLY new 0.2.0 line is under ## kit (wrong)
    printf '{ "name": "autopilot", "version": "0.2.0" }\n' \
        > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.2.0
- STALE: this 0.2.0 line already existed at BASE in the correct section

### 0.1.0
- init

## kit

### 0.2.0
- NEW added line mentioning 0.2.0 but under the WRONG (kit) section

### 0.1.0
- init
EOF
    vs_commit "$R" "bump autopilot; new 0.2.0 line under kit"
    run_versync "$R" "$base"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "autopilot"
    echo "$output" | grep -qF "0.2.0"
}

@test "version-sync DIFF: bump where version already present in section at BASE FAILS" {
    # Regression: autopilot is bumped 0.1.0 -> 0.2.0 (and a plugin file is
    # touched to trip diff-aware), but "0.2.0" was ALREADY present in autopilot's
    # OWN section at BASE — i.e. no NEW changelog entry was added for THIS bump.
    # The old HEAD-section belt-and-suspenders check would pass (0.2.0 is in the
    # section at HEAD, because it was there at BASE too). The diff-aware
    # "newly added to this section" check must reject it.
    R="${TMP}/vs-stalebase"
    vs_init "$R"
    for p in autopilot kit slicer; do
        mkdir -p "$R/plugins/$p/.claude-plugin"
    done
    printf '{ "name": "autopilot", "version": "0.1.0" }\n' > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    printf '{ "name": "kit", "version": "0.1.0" }\n'       > "$R/plugins/kit/.claude-plugin/plugin.json"
    printf '{ "name": "slicer", "version": "0.1.0" }\n'    > "$R/plugins/slicer/.claude-plugin/plugin.json"
    printf '# slicer\n\n### 0.1.0\n- init\n' > "$R/plugins/slicer/CHANGELOG.md"
    cat > "$R/CHANGELOG.md" <<'EOF'
# Changelog

## autopilot

### 0.2.0
- this 0.2.0 entry was ALREADY here at BASE

### 0.1.0
- init

## kit

### 0.1.0
- init
EOF
    vs_commit "$R" base
    base="$(git -C "$R" rev-parse HEAD)"
    # bump version to the already-present 0.2.0; touch a plugin file; add NO new
    # changelog line (the 0.2.0 entry is unchanged from BASE).
    printf '{ "name": "autopilot", "version": "0.2.0" }\n' \
        > "$R/plugins/autopilot/.claude-plugin/plugin.json"
    mkdir -p "$R/plugins/autopilot/skills"
    printf 'tweak\n' > "$R/plugins/autopilot/skills/x.md"
    vs_commit "$R" "bump to already-present 0.2.0, no new changelog line"
    run_versync "$R" "$base"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "autopilot"
    echo "$output" | grep -qF "0.2.0"
    # specifically the BASE-already-present message, proving the diff-aware check
    # (not the static check) is what catches it.
    echo "$output" | grep -qF "BASE"
}
