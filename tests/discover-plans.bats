#!/usr/bin/env bats
# SUT: plugins/autopilot/skills/batch/scripts/discover-plans.sh
# Behavior under test:
#   - lists *.md plans directly under <dir>, sorted lexicographically (ascii)
#   - emits ABSOLUTE paths, one per line
#   - excludes anything under completed/ (no recursion into subdirs)
#   - skips non-runnable plans (no "### Task N:" / "### Iteration N:" heading)
#   - errors on missing arg / missing dir

load helpers

setup() {
    make_tmpdir
    PLANS="${TMP}/plans"
    mkdir -p "$PLANS"
}

teardown() {
    cleanup_tmpdir
}

# a runnable plan: has a level-3 Task heading
make_runnable() {
    printf '# %s\n\n### Task 1: do a thing\n\n- [ ] step\n' "$1" > "${PLANS}/$1"
}

@test "errors when no plans dir argument is given" {
    run "$SUT_DISCOVER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage"* ]]
}

@test "errors when the plans dir does not exist" {
    run "$SUT_DISCOVER" "${TMP}/nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "lists a single runnable plan as an absolute path" {
    make_runnable "01-alpha.md"
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == /* ]]                 # absolute
    [[ "${lines[0]}" == */01-alpha.md ]]
}

@test "sorts multiple runnable plans lexicographically" {
    make_runnable "03-gamma.md"
    make_runnable "01-alpha.md"
    make_runnable "02-beta.md"
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ "${lines[0]}" == */01-alpha.md ]]
    [[ "${lines[1]}" == */02-beta.md ]]
    [[ "${lines[2]}" == */03-gamma.md ]]
}

@test "accepts an Iteration heading as runnable" {
    printf '# iter\n\n### Iteration 2: build\n' > "${PLANS}/iter.md"
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == */iter.md ]]
}

@test "skips a non-runnable plan (no Task/Iteration heading)" {
    printf '# notes\n\njust prose, no task heading\n' > "${PLANS}/notes.md"
    make_runnable "01-real.md"
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == */01-real.md ]]
}

@test "excludes plans living under completed/" {
    make_runnable "01-active.md"
    mkdir -p "${PLANS}/completed"
    printf '# done\n\n### Task 1: was done\n' > "${PLANS}/completed/00-done.md"
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == */01-active.md ]]
    [[ "$output" != *"00-done.md"* ]]
}

@test "ignores non-md files" {
    make_runnable "01-real.md"
    printf '### Task 1: not markdown\n' > "${PLANS}/readme.txt"
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == */01-real.md ]]
}

@test "emits nothing (exit 0) for an empty plans dir" {
    run "$SUT_DISCOVER" "$PLANS"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
