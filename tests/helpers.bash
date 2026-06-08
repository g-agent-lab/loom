# helpers.bash — shared setup/teardown + stubs for the loom bats suite.
#
# Each .bats file does `load helpers` (bats resolves it relative to the test
# file's own dir, i.e. tests/). Helpers here:
#   - REPO_ROOT / SUT_* : absolute paths to the scripts under test, so tests
#     never depend on the caller's cwd.
#   - make_tmpdir / cleanup_tmpdir : a fresh per-test scratch dir.
#   - stub_curl / curl_payload : shim `curl` onto PATH so notify.sh's
#     sendMessage path makes NO real network call; the stub records its full
#     argv so a test can assert the request shape.

# Repo root = parent of the tests/ dir that holds this helpers file.
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# Absolute paths to every script under test (full nested plugin paths).
SUT_DISCOVER="${REPO_ROOT}/plugins/autopilot/skills/batch/scripts/discover-plans.sh"
SUT_MARK="${REPO_ROOT}/plugins/autopilot/skills/batch/scripts/mark-completed.sh"
SUT_NOTIFY="${REPO_ROOT}/plugins/autopilot/skills/batch/scripts/notify.sh"
SUT_DETECT_STACK="${REPO_ROOT}/plugins/kit/skills/greenfield/scripts/detect-stack.sh"
SUT_DETECT_MODE="${REPO_ROOT}/plugins/kit/skills/greenfield/scripts/detect-mode.sh"

# Absolute paths to the top-level CHECK scripts (the marketplace guards).
SUT_VALIDATE="${REPO_ROOT}/scripts/validate-marketplace.sh"
SUT_DRIFT="${REPO_ROOT}/scripts/drift-guard.sh"
SUT_VERSYNC="${REPO_ROOT}/scripts/version-sync.sh"
SUT_LINKCHECK="${REPO_ROOT}/scripts/link-check.sh"
SUT_DOCSLINT="${REPO_ROOT}/scripts/docs-lint.sh"

# make_tmpdir — create a fresh scratch dir for the current test and export it
# as $TMP. Lives under BATS_TEST_TMPDIR (auto-cleaned by bats) but we also
# remove it ourselves in teardown for good measure.
make_tmpdir() {
    TMP="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/loom.XXXXXX")"
    export TMP
}

cleanup_tmpdir() {
    [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
    return 0
}

# stub_curl — put a fake `curl` first on PATH. It writes its entire argv (one
# arg per line) to $CURL_LOG so tests can assert the sendMessage payload shape
# without any network access. Exits 0 like a successful POST.
#
# Sets and exports: $STUB_BIN (the dir prepended to PATH) and $CURL_LOG.
stub_curl() {
    STUB_BIN="${TMP}/stub-bin"
    CURL_LOG="${TMP}/curl.log"
    mkdir -p "$STUB_BIN"
    : > "$CURL_LOG"
    cat > "${STUB_BIN}/curl" <<EOF
#!/bin/bash
# recorded fake curl — dumps argv (one per line) to the log, no network.
for a in "\$@"; do
    printf '%s\n' "\$a" >> "${CURL_LOG}"
done
exit 0
EOF
    chmod +x "${STUB_BIN}/curl"
    export PATH="${STUB_BIN}:${PATH}"
    export CURL_LOG STUB_BIN
}

# curl_payload — echo the recorded curl argv (empty if curl was never called).
curl_payload() {
    [ -f "${CURL_LOG:-/nonexistent}" ] && cat "$CURL_LOG"
}

# curl_called — succeed if the stubbed curl recorded at least one invocation.
curl_called() {
    [ -s "${CURL_LOG:-/nonexistent}" ]
}

# clear_telegram_env — unset every Telegram var so a test starts from a known
# unconfigured baseline (the host machine may have these exported).
clear_telegram_env() {
    unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID TELEGRAM_TOPIC_ID TELEGRAM_LABEL
}
