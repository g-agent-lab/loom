# Changelog

All notable changes to the **own** plugins (`autopilot`, `kit`) are recorded here.
The umputun plugins are referenced from upstream and versioned there, not here.

## autopilot

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
