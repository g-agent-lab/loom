# Reference — contracts

> The machine-checkable contracts this marketplace upholds. Most are enforced by
> a check script; where so, the enforcing script is named.

## Marketplace manifest — `.claude-plugin/marketplace.json`

Enforced by `scripts/validate-marketplace.sh` and `scripts/drift-guard.sh`.

- Top-level `name` and `owner` present.
- Exactly **3 own** entries (`autopilot`, `kit`, `slicer`) with a string
  `source` of the form `./plugins/<name>`, resolving to a dir with a
  `.claude-plugin/plugin.json` whose `name` matches and whose `version` is
  non-empty.
- Each **umputun** entry has `source.source == "git-subdir"` with a `url` and
  `path` — never a local `./plugins/...` source (that would be vendoring drift).
- No duplicate `name` keys; every entry has a non-empty `description`.
- `plugins/` on disk contains **exactly** `autopilot kit slicer` — no extra
  vendored dirs.

## Plugin manifests — `plugins/<own>/.claude-plugin/plugin.json`

Enforced by `scripts/version-sync.sh`.

- `name` matches the manifest entry; `version` non-empty.
- A changed `plugins/<own>/**` file (diff vs base in CI) requires the
  `version` at HEAD to be **semver-greater** than at base **and** that exact
  version string to appear in the plugin's changelog section
  (`## <plugin>` block in root `CHANGELOG.md`, or `plugins/slicer/CHANGELOG.md`
  for slicer). Unchanged/downgraded version → fail. Bump without changelog
  line → fail.

## autopilot ↔ loom-relay MCP contract

The `autopilot` skill's `allowed-tools` lists `mcp__loom-relay__poll_commands`,
`…__ack_commands`, `…__post_status` **statically**, so the `.mcp.json` server
**must be named exactly `loom-relay`** or every call silently no-ops. Tools
(served by the sibling `loom-relay` Worker — see
[`../plans/active/completed/01-loom-relay-hub.md`](../plans/active/completed/01-loom-relay-hub.md)):

| Tool | Signature | Effect |
|---|---|---|
| `poll_commands` | `(project, since, ack_through)` | returns commands with `id > ack_through` and `ts >= since`, ascending `id` |
| `ack_commands` | `(project, ack_through)` | advances the cursor past `ack_through`; returns nothing (terminal-case ack) |
| `post_status` | `(project, text)` | posts `text` to the project's Telegram topic (reply only — NOT the durable ack) |
| `reset_project` | `(project, …)` | maintenance: recover a queue whose cursor over-advanced |

Field contract (per project Durable Object): `id` = Telegram `update_id`;
`ts` = `message.date` (epoch seconds); `cmd` ∈ `{stop, status}`. `project` =
the **normalized git origin** (same normalization `notify.sh` uses), NOT the repo
basename.

## Telegram config files — `notify.sh`

`<plugin-data>/telegram.conf` (per machine, secret):

```
TELEGRAM_BOT_TOKEN=123456:AA...      # the only real secret
TELEGRAM_CHAT_ID=-1001234567890      # supergroup id
TELEGRAM_LABEL=home                  # optional machine tag
TELEGRAM_TOPIC_ID=                   # optional global default topic
```

`<plugin-data>/telegram-topics.conf` (per machine): `project → topic` map, keyed
by **normalized git origin** (drop `.git`, drop scheme, drop `user@`, scp
`host:path` → `host/path`, lowercase). Same key the relay's `PROJECT_ROUTES`
uses, so notifications and two-way control target the same topic.
