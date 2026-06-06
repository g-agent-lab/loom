#!/usr/bin/env bats
# SUT: plugins/kit/skills/greenfield/scripts/detect-stack.sh
#      plugins/kit/skills/greenfield/scripts/detect-mode.sh
#
# Both scripts take NO args and inspect the current working directory, so each
# test cd's into a fresh temp dir and runs the SUT there.
#
# detect-stack.sh — emits one stack id or 'unknown':
#   python-fastapi  : pyproject.toml mentioning fastapi/uvicorn
#   python-aiogram  : pyproject.toml mentioning aiogram
#   go-stdlib       : go.mod present
#   typescript-nestjs   : package.json with "@nestjs/
#   typescript-node-cli : package.json with commander/execa/@iarna/toml
#   unknown         : otherwise (incl. generic node)
#
# detect-mode.sh — emits greenfield | brownfield:
#   greenfield = no committed git history AND no linter/config markers AND no CLAUDE.md
#   anything else = brownfield

load helpers

setup() {
    make_tmpdir
    PROJ="${TMP}/proj"
    mkdir -p "$PROJ"
}

teardown() {
    cleanup_tmpdir
}

run_stack() { run bash -c "cd '$PROJ' && '$SUT_DETECT_STACK'"; }
run_mode()  { run bash -c "cd '$PROJ' && '$SUT_DETECT_MODE'"; }

# ---------- detect-stack.sh ----------

@test "detect-stack: empty project -> unknown" {
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect-stack: pyproject with fastapi -> python-fastapi" {
    printf '[project]\ndependencies = ["fastapi", "uvicorn"]\n' > "${PROJ}/pyproject.toml"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "python-fastapi" ]
}

@test "detect-stack: pyproject with uvicorn (no fastapi) -> python-fastapi" {
    # uvicorn is the alternate fastapi marker (detect-stack.sh:19 grep fastapi|uvicorn)
    printf '[project]\ndependencies = ["uvicorn"]\n' > "${PROJ}/pyproject.toml"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "python-fastapi" ]
}

@test "detect-stack: pyproject with aiogram -> python-aiogram" {
    printf '[project]\ndependencies = ["aiogram"]\n' > "${PROJ}/pyproject.toml"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "python-aiogram" ]
}

@test "detect-stack: bare pyproject (no fastapi/aiogram) -> unknown" {
    printf '[project]\nname = "x"\n' > "${PROJ}/pyproject.toml"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect-stack: go.mod -> go-stdlib" {
    printf 'module example.com/x\n\ngo 1.22\n' > "${PROJ}/go.mod"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "go-stdlib" ]
}

@test "detect-stack: package.json with @nestjs -> typescript-nestjs" {
    printf '{ "dependencies": { "@nestjs/core": "^10" } }\n' > "${PROJ}/package.json"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "typescript-nestjs" ]
}

@test "detect-stack: package.json with commander -> typescript-node-cli" {
    printf '{ "dependencies": { "commander": "^12" } }\n' > "${PROJ}/package.json"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "typescript-node-cli" ]
}

@test "detect-stack: package.json with execa -> typescript-node-cli" {
    # execa is an alternate node-cli marker (detect-stack.sh:36)
    printf '{ "dependencies": { "execa": "^8" } }\n' > "${PROJ}/package.json"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "typescript-node-cli" ]
}

@test "detect-stack: package.json with @iarna/toml -> typescript-node-cli" {
    # @iarna/toml is an alternate node-cli marker (detect-stack.sh:36)
    printf '{ "dependencies": { "@iarna/toml": "^2" } }\n' > "${PROJ}/package.json"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "typescript-node-cli" ]
}

@test "detect-stack: generic package.json (no known dep) -> unknown" {
    printf '{ "dependencies": { "left-pad": "^1" } }\n' > "${PROJ}/package.json"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect-stack: python precedence beats node when both present" {
    printf '[project]\ndependencies = ["fastapi"]\n' > "${PROJ}/pyproject.toml"
    printf '{ "dependencies": { "@nestjs/core": "^10" } }\n' > "${PROJ}/package.json"
    run_stack
    [ "$status" -eq 0 ]
    [ "$output" = "python-fastapi" ]
}

# ---------- detect-mode.sh ----------

@test "detect-mode: pristine empty dir -> greenfield" {
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "greenfield" ]
}

@test "detect-mode: git repo with a commit -> brownfield" {
    git -C "$PROJ" init -q
    git -C "$PROJ" config user.email t@t.t
    git -C "$PROJ" config user.name t
    printf 'x\n' > "${PROJ}/file.txt"
    git -C "$PROJ" add file.txt
    git -C "$PROJ" commit -qm init
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: fresh git repo with no commits -> greenfield" {
    git -C "$PROJ" init -q
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "greenfield" ]
}

@test "detect-mode: a linter config marker -> brownfield" {
    printf '[tool.ruff]\n' > "${PROJ}/pyproject.toml"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: go.mod marker -> brownfield" {
    printf 'module x\n' > "${PROJ}/go.mod"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: eslint.config.* marker -> brownfield" {
    printf 'export default []\n' > "${PROJ}/eslint.config.js"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: .eslintrc* marker -> brownfield" {
    printf '{}\n' > "${PROJ}/.eslintrc.json"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: ruff.toml marker -> brownfield" {
    printf '[lint]\n' > "${PROJ}/ruff.toml"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: .flake8 marker -> brownfield" {
    printf '[flake8]\n' > "${PROJ}/.flake8"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}

@test "detect-mode: a CLAUDE.md at root -> brownfield" {
    printf '# proj\n' > "${PROJ}/CLAUDE.md"
    run_mode
    [ "$status" -eq 0 ]
    [ "$output" = "brownfield" ]
}
