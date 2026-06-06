#!/usr/bin/env bats
# SUT: plugins/autopilot/skills/batch/scripts/mark-completed.sh
# Behavior under test:
#   - moves <plan> into <dir>/completed/ (default subdir)
#   - lazy-creates the target subdir
#   - honors a custom subdir name as the optional 2nd arg
#   - refuses to overwrite an existing target (errors, non-zero)
#   - errors on missing arg / missing plan file
#   - prints "moved: <src> -> <dst>" on success

load helpers

setup() {
    make_tmpdir
    PLANS="${TMP}/plans"
    mkdir -p "$PLANS"
    PLAN="${PLANS}/01-plan.md"
    printf '# plan\n\n### Task 1: x\n' > "$PLAN"
}

teardown() {
    cleanup_tmpdir
}

@test "errors when no plan argument is given" {
    run "$SUT_MARK"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "usage"
}

@test "errors when the plan file does not exist" {
    run "$SUT_MARK" "${PLANS}/nope.md"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "not found"
}

@test "moves the plan into completed/ and lazy-creates the subdir" {
    [ ! -d "${PLANS}/completed" ]            # subdir absent beforehand
    run "$SUT_MARK" "$PLAN"
    [ "$status" -eq 0 ]
    [ -d "${PLANS}/completed" ]              # created lazily
    [ -f "${PLANS}/completed/01-plan.md" ]   # moved in
    [ ! -f "$PLAN" ]                         # gone from source
    echo "$output" | grep -qF "moved:"
}

@test "honors a custom completed-subdir name" {
    run "$SUT_MARK" "$PLAN" "archive"
    [ "$status" -eq 0 ]
    [ -f "${PLANS}/archive/01-plan.md" ]
    [ ! -f "$PLAN" ]
    [ ! -d "${PLANS}/completed" ]            # default subdir NOT created
    echo "$output" | grep -qF "moved:"      # success message emitted
}

@test "reuses an existing completed/ dir (does not require lazy create)" {
    mkdir -p "${PLANS}/completed"
    run "$SUT_MARK" "$PLAN"
    [ "$status" -eq 0 ]
    [ -f "${PLANS}/completed/01-plan.md" ]
}

@test "refuses to overwrite an existing target file" {
    mkdir -p "${PLANS}/completed"
    printf 'pre-existing\n' > "${PLANS}/completed/01-plan.md"
    run "$SUT_MARK" "$PLAN"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qF "already exists"
    [ -f "$PLAN" ]                                       # source untouched
    [ "$(cat "${PLANS}/completed/01-plan.md")" = "pre-existing" ]  # target untouched
}
