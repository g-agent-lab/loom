#!/bin/bash
# notify.sh — best-effort Telegram notification for the autopilot queue
# usage: notify.sh <plugin-data-dir> <message text...>
#
# <plugin-data-dir> is the resolved $CLAUDE_PLUGIN_DATA, passed EXPLICITLY as the
# first argument. It must be passed in — the same way the skill passes it to
# resolve-rules.sh — because $CLAUDE_PLUGIN_DATA is NOT reliably exported into a
# Bash subprocess (Claude Code substitutes the ${CLAUDE_PLUGIN_DATA} placeholder
# into the command text, but the live env var inside the shell points elsewhere
# or is empty). May be empty; the script then falls back to the env var, and
# finally to a sibling-dir search (see below).
#
# Designed for a shared bot used from multiple machines, routing each project to
# its own forum topic in one supergroup. NOTHING here is ever stored in a project
# repo — all ids live in the per-machine plugin data dir.
#
# Credential / routing resolution (env always wins, then the conf files):
#
#   <plugin-data-dir>/telegram.conf            (secret; per machine)
#       TELEGRAM_BOT_TOKEN=123456:AA...        # the ONLY real secret
#       TELEGRAM_CHAT_ID=-1001234567890        # supergroup id
#       TELEGRAM_LABEL=home                    # optional machine tag (home/work)
#       TELEGRAM_TOPIC_ID=                      # optional global default topic
#
#   <plugin-data-dir>/telegram-topics.conf     (project -> topic map; per machine)
#       github.com/me/proj-a = 42              # key = normalized `git remote origin`
#       github.com/me/proj-b = 77
#
# Sibling-dir fallback: the data dir Claude Code resolves depends on how the
# plugin is installed (marketplace `autopilot-loom` vs inline `autopilot-inline`).
# If the passed/env dir has no usable token, the script searches every
# `autopilot-*` data dir under the same `plugins/data` root and uses the first
# conf that carries a token — so credentials placed in either sibling work, and
# an install-context mismatch can no longer mask delivery. The topics map is then
# read from the SAME dir the token was found in, so they always travel together.
#
# The project topic is looked up by the normalized origin remote URL (identical on
# every machine that cloned the same repo), falling back to the repo dir name.
#
# Why ids are not committed: only the bot token can actually post; chat/topic ids
# are not credentials. But keeping them out of any (esp. public) repo avoids
# revealing internal group layout and limits blast radius if a token ever leaks.
#
# Notifications are strictly opt-in: with no token+chat resolved, this exits 0
# silently. Network/API errors are swallowed too. This script ALWAYS exits 0 —
# a notification must never block or stall a queue run. Message text is sent as
# plain text (no Markdown parse mode), so special characters are safe.

data_dir="$1"
shift 2>/dev/null || true
msg="$*"
[ -z "$msg" ] && exit 0

# the data dir may also arrive via env (legacy / direct invocation)
data_dir="${data_dir:-$CLAUDE_PLUGIN_DATA}"

# 1. seed from environment (highest precedence)
token="$TELEGRAM_BOT_TOKEN"
chat="$TELEGRAM_CHAT_ID"
topic="$TELEGRAM_TOPIC_ID"
label="$TELEGRAM_LABEL"

# 2. pick the conf file: the resolved data dir, then a sibling-dir search
conf=""
if [ -n "$data_dir" ] && [ -f "$data_dir/telegram.conf" ] \
   && grep -q '^[[:space:]]*TELEGRAM_BOT_TOKEN=..*' "$data_dir/telegram.conf" 2>/dev/null; then
    conf="$data_dir/telegram.conf"
fi

if [ -z "$conf" ] && [ -z "$token" ]; then
    # derive the plugins/data root: parent of the passed dir, else the default
    if [ -n "$data_dir" ]; then
        data_root="$(dirname "$data_dir")"
    else
        data_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data"
    fi
    for cand in "$data_root"/autopilot-*/telegram.conf; do
        [ -f "$cand" ] || continue
        if grep -q '^[[:space:]]*TELEGRAM_BOT_TOKEN=..*' "$cand" 2>/dev/null; then
            conf="$cand"
            data_dir="$(dirname "$cand")"
            break
        fi
    done
fi

# 3. fill any blanks from the chosen conf file
if [ -n "$conf" ] && [ -f "$conf" ]; then
    # shellcheck disable=SC1090
    . "$conf"
    token="${token:-$TELEGRAM_BOT_TOKEN}"
    chat="${chat:-$TELEGRAM_CHAT_ID}"
    topic="${topic:-$TELEGRAM_TOPIC_ID}"
    label="${label:-$TELEGRAM_LABEL}"
fi

# not configured → silent no-op, success exit
[ -z "$token" ] && exit 0
[ -z "$chat" ] && exit 0

# 4. resolve the per-project topic from the map (only when not already set)
map="$data_dir/telegram-topics.conf"
if [ -z "$topic" ] && [ -n "$data_dir" ] && [ -f "$map" ]; then
    # project key: normalize the origin remote so ssh and https forms match, and
    # so both machines that cloned the same repo resolve the identical key.
    key="$(git remote get-url origin 2>/dev/null || true)"
    if [ -n "$key" ]; then
        key="${key%.git}"        # drop trailing .git
        key="${key#*://}"        # drop scheme:// (https/git/ssh)
        key="${key#*@}"          # drop user@ (ssh)
        key="${key/:/\/}"        # scp form host:path -> host/path
    else
        key="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
    fi
    key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"

    topic="$(awk -F'=' -v k="$key" '
        { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2) }
        $1 == k { print $2; exit }
    ' "$map")"
fi

# 5. machine label prefix (so home/work are distinguishable in a shared topic)
[ -n "$label" ] && msg="[$label] $msg"

# 6. fire and forget
set -- \
    -sS --max-time 10 \
    -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "disable_web_page_preview=true"
[ -n "$topic" ] && set -- "$@" --data-urlencode "message_thread_id=${topic}"

curl "$@" >/dev/null 2>&1 || true

exit 0
