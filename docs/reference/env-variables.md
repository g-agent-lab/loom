# Reference — environment variables

> Every environment variable **read but never assigned** in the repo's shell
> scripts (`git ls-files '*.sh'`). Enforced by `scripts/docs-lint.sh`: a script
> reading an undocumented external var fails CI. No secret values live here — only
> names, sources, and where the real values come from.

## Telegram notifications — `plugins/autopilot/skills/batch/scripts/notify.sh`

Resolved from the per-machine `telegram.conf` (in the plugin data dir) or the
process environment; never committed.

| Variable | Secret | Purpose |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | **yes** | Bot token for `sendMessage`. The only real secret. |
| `TELEGRAM_CHAT_ID` | no | Supergroup chat id (shared across projects). |
| `TELEGRAM_TOPIC_ID` | no | Optional explicit topic id; overrides the per-project topic map. |
| `TELEGRAM_LABEL` | no | Optional machine tag (e.g. `home`/`work`) prefixed to messages. |

Config files (per machine, not in the repo): `<plugin-data>/telegram.conf`
(the four vars above) and `<plugin-data>/telegram-topics.conf` (project →
topic map, keyed by normalized git origin). See
[`contracts.md`](contracts.md) for the file formats.

## Claude Code injected — autopilot scripts & `resolve-rules.sh`

| Variable | Purpose |
|---|---|
| `CLAUDE_CONFIG_DIR` | Claude config root (defaults to `~/.claude`); used to locate the plugin data dir for the sibling-`autopilot-*` token fallback. |
| `CLAUDE_PLUGIN_DATA` | Resolved plugin data dir, passed explicitly into Bash subprocesses (the `${CLAUDE_PLUGIN_DATA}` placeholder is not reliably exported). |

> `CLAUDE_PLUGIN_ROOT` is also used, but only inside `SKILL.md` (e.g.
> `${CLAUDE_PLUGIN_ROOT}/references/relay-control.md`), not in any `*.sh`, so
> docs-lint does not track it. Listed here for completeness.

## kit bootstrap — `plugins/kit/skills/greenfield/scripts/ensure-kit.sh`

Override the llm-kit install when bootstrapping a target project.

| Variable | Default | Purpose |
|---|---|---|
| `KIT_SOURCE` | `https://github.com/g-agent-lab/llm-kit.git` | Git URL of the llm-kit canon. |
| `KIT_INSTALL_METHOD` | `submodule` | `submodule` \| `copy` \| `local`. |
| `KIT_INSTALL_PATH` | `external/llm-kit` | Where llm-kit lands in the target project. |
| `KIT_LOCAL_PATH` | _(empty)_ | Absolute path to a local llm-kit checkout (when method=`local`). |

## kit verify — `plugins/kit/skills/greenfield/scripts/verify-step.sh`

| Variable | Purpose |
|---|---|
| `LINT_COMMAND` | Stack-specific lint command the verify step runs for the `lint-passes` check. |

## CI — `scripts/version-sync.sh`

| Variable | Purpose |
|---|---|
| `BASE` | Diff base ref for version-sync's diff-aware mode. Resolved by `.github/workflows/ci.yml` (PR base SHA, or `github.event.before` on push) and passed as the arg / `$BASE` env. Empty → static fallback. |
