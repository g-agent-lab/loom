#!/usr/bin/env bats
# SUT: plugins/autopilot/skills/batch/scripts/notify.sh
#   usage: notify.sh <plugin-data-dir> <message text...>
#
# Behavior under test:
#   - empty message  -> exit 0, no curl
#   - unconfigured (no token / no chat) -> silent no-op, exit 0, no curl
#   - credential resolution precedence: env > telegram.conf in passed dir
#   - sibling autopilot-* fallback when the passed dir lacks a token
#   - per-project topic lookup by normalized git origin (telegram-topics.conf)
#   - machine label prefixes the message text
#   - sendMessage payload shape (chat_id / text / disable_web_page_preview,
#     and message_thread_id only when a topic resolves)
#
# Network is shimmed: stub_curl puts a fake curl on PATH that records argv and
# never hits the wire. The SUT always exits 0 regardless.

load helpers

setup() {
    make_tmpdir
    clear_telegram_env
    stub_curl
    # the per-machine plugin data dir layout: <root>/autopilot-loom/...
    DATA_ROOT="${TMP}/plugins/data"
    DATA_DIR="${DATA_ROOT}/autopilot-loom"
    mkdir -p "$DATA_DIR"
    # keep the sibling-search default root (~/.claude) from ever matching by
    # pointing CLAUDE_CONFIG_DIR at an empty dir.
    export CLAUDE_CONFIG_DIR="${TMP}/empty-claude"
    mkdir -p "${CLAUDE_CONFIG_DIR}/plugins/data"
    unset CLAUDE_PLUGIN_DATA
}

teardown() {
    cleanup_tmpdir
}

# write a telegram.conf into a given data dir
write_conf() {
    local dir="$1"; shift
    printf '%s\n' "$@" > "${dir}/telegram.conf"
}

# extract the value of a --data-urlencode k=v pair from the recorded curl argv
payload_value() {
    local key="$1"
    # lines look like:  chat_id=-100123   (the value arg follows --data-urlencode)
    curl_payload | grep -E "^${key}=" | head -1 | sed -E "s/^${key}=//"
}

@test "empty message is a no-op (exit 0, no curl)" {
    run "$SUT_NOTIFY" "$DATA_DIR"
    [ "$status" -eq 0 ]
    run curl_called
    [ "$status" -ne 0 ]
}

@test "unconfigured (no token anywhere) is a silent no-op exit 0" {
    run "$SUT_NOTIFY" "$DATA_DIR" "hello world"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run curl_called
    [ "$status" -ne 0 ]
}

@test "token present but no chat -> still a no-op exit 0" {
    write_conf "$DATA_DIR" "TELEGRAM_BOT_TOKEN=123:AAtoken"
    run "$SUT_NOTIFY" "$DATA_DIR" "hi"
    [ "$status" -eq 0 ]
    run curl_called
    [ "$status" -ne 0 ]
}

@test "resolves token+chat from telegram.conf and POSTs sendMessage" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=123:AAtoken" \
        "TELEGRAM_CHAT_ID=-1009999"
    run "$SUT_NOTIFY" "$DATA_DIR" "queue done"
    [ "$status" -eq 0 ]
    run curl_called
    [ "$status" -eq 0 ]
    # endpoint carries the token
    curl_payload | grep -q 'https://api.telegram.org/bot123:AAtoken/sendMessage'
    # payload fields
    [ "$(payload_value chat_id)" = "-1009999" ]
    [ "$(payload_value text)" = "queue done" ]
    [ "$(payload_value disable_web_page_preview)" = "true" ]
    # no topic resolved -> no message_thread_id
    run bash -c "cat '$CURL_LOG' | grep -c 'message_thread_id'"
    [ "$output" = "0" ]
}

@test "environment token+chat win over (and work without) a conf file" {
    export TELEGRAM_BOT_TOKEN="999:ENVTOK"
    export TELEGRAM_CHAT_ID="-100ENV"
    run "$SUT_NOTIFY" "$DATA_DIR" "env wins"
    [ "$status" -eq 0 ]
    curl_payload | grep -q 'bot999:ENVTOK/sendMessage'
    [ "$(payload_value chat_id)" = "-100ENV" ]
}

@test "env token takes precedence over a different conf token" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=CONF:tok" \
        "TELEGRAM_CHAT_ID=-100CONF"
    export TELEGRAM_BOT_TOKEN="ENV:tok"
    run "$SUT_NOTIFY" "$DATA_DIR" "precedence"
    [ "$status" -eq 0 ]
    curl_payload | grep -q 'botENV:tok/sendMessage'
    # chat still fills from conf (env chat unset)
    [ "$(payload_value chat_id)" = "-100CONF" ]
}

@test "machine label prefixes the message text" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=123:AAtoken" \
        "TELEGRAM_CHAT_ID=-1009999" \
        "TELEGRAM_LABEL=home"
    run "$SUT_NOTIFY" "$DATA_DIR" "ping"
    [ "$status" -eq 0 ]
    [ "$(payload_value text)" = "[home] ping" ]
}

@test "sibling autopilot-* fallback finds a token in a sibling data dir" {
    # passed dir (autopilot-loom) has NO token; sibling autopilot-inline does.
    SIB="${DATA_ROOT}/autopilot-inline"
    mkdir -p "$SIB"
    write_conf "$SIB" \
        "TELEGRAM_BOT_TOKEN=SIB:tok" \
        "TELEGRAM_CHAT_ID=-100SIB"
    run "$SUT_NOTIFY" "$DATA_DIR" "via sibling"
    [ "$status" -eq 0 ]
    run curl_called
    [ "$status" -eq 0 ]
    curl_payload | grep -q 'botSIB:tok/sendMessage'
    [ "$(payload_value chat_id)" = "-100SIB" ]
}

@test "topic resolves by normalized git origin from telegram-topics.conf" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=123:AAtoken" \
        "TELEGRAM_CHAT_ID=-1009999"
    # topics map keyed by normalized origin (scheme/user/.git stripped, lowercased)
    printf 'github.com/me/proj-a = 42\n' > "${DATA_DIR}/telegram-topics.conf"

    # a temp git repo whose origin normalizes to that key
    REPO="${TMP}/proj"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "https://github.com/me/proj-a.git"

    run bash -c "cd '$REPO' && '$SUT_NOTIFY' '$DATA_DIR' 'topic test'"
    [ "$status" -eq 0 ]
    [ "$(payload_value message_thread_id)" = "42" ]
    [ "$(payload_value chat_id)" = "-1009999" ]
}

@test "ssh-form origin normalizes to the same topic key" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=123:AAtoken" \
        "TELEGRAM_CHAT_ID=-1009999"
    printf 'github.com/me/proj-a = 77\n' > "${DATA_DIR}/telegram-topics.conf"

    REPO="${TMP}/proj-ssh"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "git@github.com:me/proj-a.git"

    run bash -c "cd '$REPO' && '$SUT_NOTIFY' '$DATA_DIR' 'ssh topic'"
    [ "$status" -eq 0 ]
    [ "$(payload_value message_thread_id)" = "77" ]
}

@test "no matching topic key -> no message_thread_id but still posts" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=123:AAtoken" \
        "TELEGRAM_CHAT_ID=-1009999"
    printf 'github.com/me/other = 9\n' > "${DATA_DIR}/telegram-topics.conf"

    REPO="${TMP}/proj-nomatch"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "https://github.com/me/unmapped.git"

    run bash -c "cd '$REPO' && '$SUT_NOTIFY' '$DATA_DIR' 'no topic'"
    [ "$status" -eq 0 ]
    run curl_called
    [ "$status" -eq 0 ]
    run bash -c "grep -c 'message_thread_id' '$CURL_LOG'"
    [ "$output" = "0" ]
}

@test "explicit TELEGRAM_TOPIC_ID env wins over the map lookup" {
    write_conf "$DATA_DIR" \
        "TELEGRAM_BOT_TOKEN=123:AAtoken" \
        "TELEGRAM_CHAT_ID=-1009999"
    printf 'github.com/me/proj-a = 42\n' > "${DATA_DIR}/telegram-topics.conf"
    export TELEGRAM_TOPIC_ID="500"

    REPO="${TMP}/proj-env-topic"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "https://github.com/me/proj-a.git"

    run bash -c "cd '$REPO' && '$SUT_NOTIFY' '$DATA_DIR' 'env topic'"
    [ "$status" -eq 0 ]
    [ "$(payload_value message_thread_id)" = "500" ]
}
