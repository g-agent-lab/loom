#!/bin/bash
# notify.sh — best-effort Telegram notification for the autopilot queue
# usage: notify.sh <message text...>
#
# Designed for a shared bot used from multiple machines, routing each project to
# its own forum topic in one supergroup. NOTHING here is ever stored in a project
# repo — all ids live in the per-machine plugin data dir.
#
# Credential / routing resolution (env always wins, then the conf files):
#
#   $CLAUDE_PLUGIN_DATA/telegram.conf          (secret; per machine)
#       TELEGRAM_BOT_TOKEN=123456:AA...        # the ONLY real secret
#       TELEGRAM_CHAT_ID=-1001234567890        # supergroup id
#       TELEGRAM_LABEL=home                    # optional machine tag (home/work)
#       TELEGRAM_TOPIC_ID=                      # optional global default topic
#
#   $CLAUDE_PLUGIN_DATA/telegram-topics.conf   (project -> topic map; per machine)
#       github.com/me/proj-a = 42              # key = normalized `git remote origin`
#       github.com/me/proj-b = 77
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

msg="$*"
[ -z "$msg" ] && exit 0

# 1. seed from environment (highest precedence)
token="$TELEGRAM_BOT_TOKEN"
chat="$TELEGRAM_CHAT_ID"
topic="$TELEGRAM_TOPIC_ID"
label="$TELEGRAM_LABEL"

# 2. fill any blanks from the per-machine conf file
conf="$CLAUDE_PLUGIN_DATA/telegram.conf"
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -f "$conf" ]; then
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

# 3. resolve the per-project topic from the map (only when not already set)
map="$CLAUDE_PLUGIN_DATA/telegram-topics.conf"
if [ -z "$topic" ] && [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -f "$map" ]; then
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

# 4. machine label prefix (so home/work are distinguishable in a shared topic)
[ -n "$label" ] && msg="[$label] $msg"

# 5. fire and forget
set -- \
    -sS --max-time 10 \
    -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "disable_web_page_preview=true"
[ -n "$topic" ] && set -- "$@" --data-urlencode "message_thread_id=${topic}"

curl "$@" >/dev/null 2>&1 || true

exit 0
