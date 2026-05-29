# autopilot — Telegram notifications

Opt-in progress notifications for a queue run. The queue pushes a message to a
Telegram chat at queue start, on each plan (configurable), on any failure, and at
the final summary — so you can start a 4-plan run and watch it from your phone.

Built for a **shared bot used from several machines** (home + work), routing each
project into its **own forum topic** of a single supergroup. No Telegram id ever
lives in a project repo — everything stays in the per-machine plugin data dir.

Everything is **best-effort**: if notifications are unconfigured or the network
hiccups, the queue runs exactly as before. A notification never blocks, retries,
or fails a run.

## What you get

```
🏠 home: 🚀 loom-marketplace [master] — queue: 4 plan(s)
🏠 home: ▶️ loom-marketplace [2/4] 02-api.md — running
🏠 home: ✅ loom-marketplace [2/4] 02-api.md — done → completed/
🏠 home: ❌ loom-marketplace [3/4] 03-ui.md — FAILED (3 tasks unchecked)
🏠 home: 🏁 loom-marketplace [master] — done: 3 ok, 1 failed, 0 skipped
```

Each message names the **machine** (label), **project** (repo dir) and **branch**,
the plan's **N/M** position, and status — covering "which machine, which project,
which plan, in-progress, failed/not failed" at a glance, all inside that project's
own topic.

## Multiple machines, one bot — the model

Telegram facts this design relies on (Bot API):

- `sendMessage` only ever **appends** a new message. Two machines posting to the
  same chat **never overwrite** each other — only the separate `editMessageText`
  method edits, and we don't use it. So there is **no collision**.
- `sendMessage` takes `message_thread_id` (Integer) → the forum **topic** in a
  supergroup. One supergroup, one topic per project.

So both machines share the same bot token + supergroup, and each project maps to
one topic. Both home and work post that project's events into the **same topic**,
distinguished by the machine label. No conflict, no overwriting.

### What is secret, what is not

The **bot token is the only credential** — without it nobody can post, even
knowing the chat/topic ids. Chat id and topic ids are therefore not secrets. We
still keep them out of repos (especially public ones): publishing internal group
ids reveals your infra layout and widens the blast radius if a token ever leaks.
Cost of keeping them local is ~zero, so we do.

## One-time setup (per machine)

### 1. Bot token

You already have a bot. Grab its token from [@BotFather](https://t.me/BotFather)
(`/mybots` → your bot → API Token), or `/newbot` for a new one.

### 2. Supergroup (chat) id and topic ids

In the supergroup, the simplest way to read ids: temporarily allow the bot to
read messages, post once in the **General** area and once in each project **topic**,
then open:

```
https://api.telegram.org/bot<token>/getUpdates
```

- `"chat":{"id":-1001234567890,...}` → the **supergroup** id (one, shared).
- `"message_thread_id":42` on a message posted inside a topic → that **topic** id.

(Forum topics must be enabled: supergroup → Edit → Topics.)

### 3. Credentials file — `$CLAUDE_PLUGIN_DATA/telegram.conf`

```
TELEGRAM_BOT_TOKEN=123456:AAH...
TELEGRAM_CHAT_ID=-1001234567890
TELEGRAM_LABEL=home              # 🏠 home / 💼 work — distinguishes machines
```

Ask Claude during a session ("set up telegram notifications for autopilot") and it
writes this for you, or create it by hand. `$CLAUDE_PLUGIN_DATA` is set by Claude
Code for marketplace-installed plugins; if it is unset, export `TELEGRAM_BOT_TOKEN`
/ `TELEGRAM_CHAT_ID` / `TELEGRAM_LABEL` in your shell instead.

### 4. Project → topic map — `$CLAUDE_PLUGIN_DATA/telegram-topics.conf`

```
# key = normalized `git remote get-url origin`  (scheme/user@/.git stripped, lowercased,
#       ssh host:path rewritten to host/path) — identical on every clone of the repo
github.com/me/proj-a = 42
github.com/me/proj-b = 77
```

`notify.sh` computes the current repo's key from its `origin` remote (falling back
to the repo directory name when there is no remote) and looks up the topic. No
match → messages go to the supergroup's General area.

### 5. Second machine

Copy the **same two files** into that machine's `$CLAUDE_PLUGIN_DATA`, changing
only `TELEGRAM_LABEL` (e.g. `work`). Because the topic map is keyed by the origin
remote, both machines route each project to the identical topic automatically.

## Controls (userConfig)

| Key | Default | Purpose |
|---|---|---|
| `notify` | `true` | Master switch. `false` mutes everything without removing credentials. |
| `notify_level` | `per_plan` | `per_plan` = start + every plan start/result + summary. `summary` = queue start + failures + summary only. |

With `notify` on but no credentials present, notifications are a silent no-op —
so leaving the default `true` is harmless until you configure a token.

## Precedence

For every value: **environment variable** wins, then `telegram.conf`. The topic is
resolved as: `TELEGRAM_TOPIC_ID` env → `telegram.conf` → `telegram-topics.conf`
lookup by project key.

## Customising messages

The wording lives in the `batch` skill's `Telegram Notifications` section
(`SKILL.md`); the machine label and topic routing are added by `notify.sh`
transparently. To tweak phrasing per project without editing the plugin, add a
`.claude/queue-rules.md` instruction (see [custom-rules.md](./custom-rules.md)).

## Scope

Notifications cover the **autopilot queue** (`/autopilot:run`). A standalone
`/planning:exec` run (umputun's plugin, not edited here) is not covered — wrap
plans in a queue to get notifications, or add a Claude Code `Stop` hook for
single runs.
