# Changelog

All notable changes to the **own** plugins (`autopilot`, `kit`) are recorded here.
The umputun plugins are referenced from upstream and versioned there, not here.

## autopilot

### 0.5.0 — 2026-06-06
- **Removed the `relay_control` userConfig.** Two-way control (`/stop`, `/status`)
  now activates **automatically whenever the `loom-relay` MCP server is connected** —
  the server's presence is the opt-in, `claude mcp remove loom-relay` is the opt-out.
  Rationale: Claude Code only lets a plugin's userConfig be flipped in the
  interactive `/plugin` UI (no CLI, no settings file), so gating an MCP-driven
  feature on a userConfig toggle made setup un-scriptable. The MCP tools'
  availability is already the real signal; the toggle was redundant friction.
- Docs now recommend supplying the Cloudflare Access service-token via a
  `headersHelper` script (reads the token from a local file, emits headers as JSON
  at connect time) instead of `${...}` env-expansion. This makes control connect
  **regardless of how Claude Code was launched** (stale terminal / GUI / IDE), where
  env-expansion silently expanded to empty and failed Access. Env-expansion stays
  documented as the simpler alternative.
- Behavior is otherwise identical to 0.4.0: boundary-only checks, at-least-once ack,
  never blocks the queue, `notify.sh` one-way progress untouched.

### 0.4.0 — 2026-06-06
- Worktree hint: before each `/planning:exec` invoke, print a deterministic banner
  (keyed by the worktree strategy) telling the operator how to answer
  `planning:exec`'s own unavoidable isolation question. `WT` is normalized to a
  canonical `per_plan` / `shared` / `none` enum.
- Two-way control via the separate `loom-relay` MCP hub (opt-in `relay_control`,
  default off): send `/stop` (graceful halt after the current plan) and `/status`
  (live counters) from Telegram. autopilot no longer touches Telegram for intake —
  it calls the hub's `poll_commands` / `ack_commands` / `post_status` tools at plan
  boundaries only. Replaces the abandoned in-plugin `getUpdates` polling design
  (unsound for a shared multi-machine bot). `notify.sh` (one-way progress) is
  unchanged.
- New `relay_control` userConfig. The `.mcp.json` server MUST be named exactly
  `loom-relay` (static tool names) or control silently no-ops. Added
  `references/relay-control.md`.

### 0.3.1 — 2026-06-02
- Fix Telegram notifications silently never sending. Two root causes: (1)
  `notify.sh` read `$CLAUDE_PLUGIN_DATA` from the Bash subprocess env, where it is
  not reliably set — unlike `resolve-rules.sh`, which receives it as an argument.
  The skill now passes the data dir as `notify.sh`'s first argument. (2) The data
  dir Claude Code resolves depends on install context (`autopilot-loom` vs
  `autopilot-inline`); a token placed in the other sibling was invisible.
  `notify.sh` now falls back to searching every `autopilot-*` data dir for a
  configured token and reads the topics map from the same dir — so credentials in
  either sibling deliver, surviving plugin reinstalls without duplicating config.

### 0.3.0 — 2026-05-29
- Opt-in Telegram progress notifications for queue runs: queue start, per-plan
  start/result, failures, and final summary — each message tagged with machine
  label, project, branch, and plan N/M position.
- New `notify` (master switch) and `notify_level` (`per_plan` | `summary`)
  userConfig keys.
- Multi-machine, shared-bot design: both machines post to one supergroup with no
  collision (`sendMessage` only appends). Each project routes to its own forum
  topic via `message_thread_id`, looked up by normalized `git remote origin` from
  `$CLAUDE_PLUGIN_DATA/telegram-topics.conf`. Machine label (`TELEGRAM_LABEL`)
  prefixes every message to distinguish home/work.
- All Telegram ids stay in `$CLAUDE_PLUGIN_DATA` (or env) — never committed to a
  repo. The bot token is the only real secret; ids are kept local as hygiene.
- Best-effort by design: a notification never blocks, retries, or fails a run;
  unconfigured = silent no-op.
- Added `scripts/notify.sh` and `references/telegram-setup.md`.

### 0.2.0 — 2026-05-29
- Renamed from `queue` to `autopilot` as part of the `loom` marketplace launch.
- Pre-flight idempotent success check: a plan already fully `[x]` on entry is
  treated as success and moved to `completed/` without re-running `/planning:exec`.
- Bilingual skill triggers (English + Russian).

### 0.1.0
- Initial sequential plan runner: discover plans in `docs/plans/active/`, run each
  through `/planning:exec`, verify checkboxes, move to `completed/`, loop.

## kit

### 0.1.0 — 2026-05-29
- Initial release in the `loom` marketplace (formerly standalone `cc-kit`).
- Greenfield + brownfield llm-kit bootstrap driver; reads the llm-kit playbook live.
- Bilingual skill triggers (English + Russian).
