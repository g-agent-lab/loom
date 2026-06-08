#!/usr/bin/env bats
# SUT: scripts/docs-lint.sh
#
# FAIL-path + positive-control tests for the docs-lint guard. CI only runs it
# against the live (passing) repo; without these a guard refactored into a no-op
# would keep CI green. docs-lint accepts a [repo-root] arg; its env-var and
# plans/active checks read `git ls-files`, so those fixtures are throwaway git
# repos. The required-docs check needs no git.

load helpers

setup() {
    make_tmpdir
}

teardown() {
    cleanup_tmpdir
}

# dl_fixture ROOT — a minimal repo that PASSES docs-lint: the four required
# docs, an env-variables.md, and a trivial tracked script. Committed so
# `git ls-files` sees everything. Caller then mutates to break one invariant.
dl_fixture() {
    local R="$1"
    mkdir -p "$R/docs/reference" "$R/docs/plans/active" "$R/scripts"
    printf '# CONTEXT\n'    > "$R/docs/CONTEXT.md"
    printf '# DOCS_RULES\n' > "$R/docs/DOCS_RULES.md"
    printf '# SESSION\n'    > "$R/docs/SESSION.md"
    printf '# ROADMAP\n'    > "$R/docs/plans/ROADMAP.md"
    printf '# env vars\n'   > "$R/docs/reference/env-variables.md"
    printf '#!/bin/bash\necho hi\n' > "$R/scripts/noop.sh"
    git -C "$R" init -q
    git -C "$R" config user.email t@t.t
    git -C "$R" config user.name t
    git -C "$R" add -A
    git -C "$R" commit -qm base
}

@test "docs-lint: a passing fixture exits 0" {
    R="${TMP}/ok"
    dl_fixture "$R"
    run "$SUT_DOCSLINT" "$R"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "OK"
}

@test "docs-lint: a missing required doc FAILS" {
    R="${TMP}/nodoc"
    dl_fixture "$R"
    rm "$R/docs/CONTEXT.md"
    run "$SUT_DOCSLINT" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "missing required doc"
    echo "$output" | grep -qF "CONTEXT.md"
}

@test "docs-lint: an undocumented env var read in a script FAILS" {
    R="${TMP}/undocenv"
    dl_fixture "$R"
    # a script that READS $NEW_SECRET (never assigned, not in env-variables.md)
    printf '#!/bin/bash\necho "$NEW_SECRET"\n' > "$R/scripts/leak.sh"
    git -C "$R" add -A
    git -C "$R" commit -qm "add script reading NEW_SECRET"
    run "$SUT_DOCSLINT" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "NEW_SECRET"
    echo "$output" | grep -qF "not documented"
}

@test "docs-lint: documenting that env var makes it PASS" {
    R="${TMP}/docenv"
    dl_fixture "$R"
    printf '#!/bin/bash\necho "$NEW_SECRET"\n' > "$R/scripts/leak.sh"
    printf '# env vars\n\n- `NEW_SECRET` — a thing\n' > "$R/docs/reference/env-variables.md"
    git -C "$R" add -A
    git -C "$R" commit -qm "document NEW_SECRET"
    run "$SUT_DOCSLINT" "$R"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "OK"
}

@test "docs-lint: an ASSIGNED all-caps var is not required in env-variables.md" {
    # a var assigned in-script (a local, not external config) must NOT be flagged
    R="${TMP}/assigned"
    dl_fixture "$R"
    printf '#!/bin/bash\nLOCAL_THING=$(date)\necho "$LOCAL_THING"\n' > "$R/scripts/local.sh"
    git -C "$R" add -A
    git -C "$R" commit -qm "add script with an assigned local"
    run "$SUT_DOCSLINT" "$R"
    [ "$status" -eq 0 ]
    # the assigned var must not surface as an undocumented-env error
    [ "$output" = "${output/LOCAL_THING/}" ]
}

@test "docs-lint: a plan in active/ without a draft reference FAILS" {
    R="${TMP}/nodraft"
    dl_fixture "$R"
    printf '# a plan\n\nno draft link here\n' > "$R/docs/plans/active/01-thing.md"
    git -C "$R" add -A
    git -C "$R" commit -qm "add active plan with no draft ref"
    run "$SUT_DOCSLINT" "$R"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "does not reference a draft"
}

@test "docs-lint: the live repo PASSES (positive control)" {
    run "$SUT_DOCSLINT" "$REPO_ROOT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "OK"
}
