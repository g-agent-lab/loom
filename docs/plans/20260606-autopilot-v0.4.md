# autopilot v0.4.0 — worktree hint + two-way Telegram (/stop, /status)

## Overview

Two operator-facing improvements to the `autopilot` plugin, shipped together as **v0.4.0**:

1. **Worktree hint ("Own + hint").** autopilot keeps owning worktree isolation, but
   prints a deterministic guidance banner before each `/planning:exec` call so the
   operator knows how to answer `planning:exec`'s own (unavoidable) isolation question.
   This trivializes the second of the two worktree prompts per plan.
2. **Two-way Telegram control.** A new opt-in `telegram_control` mode lets the operator
   send `/stop` (graceful halt after the current plan) and `/status` (reply with live
   counters) from their phone. Commands are polled at **plan boundaries only** — there is
   no mid-plan interruption (the session is busy inside `/planning:exec`).

Problem solved: the queue is currently one-way (push notifications only) and double-asks
about worktrees. This adds lightweight remote control and removes friction, without
forking the upstream `planning` plugin.

## Acceptance Criteria

- The worktree hint banner is printed before every `/planning:exec` invoke, with the correct
  string for each of the three strategies (`per_plan`, `shared`, `none`).
- `/stop` halts the queue gracefully after the current plan (remaining → skipped, ack sent);
  `/status` replies with live counters and does not change control flow.
- All two-way polling is gated behind `telegram_control` (default `false`); with it off, the
  queue behaves exactly as v0.3.1.
- `notify.sh` behavior is unchanged after the `_tg-resolve.sh` refactor (same CLI, silent
  no-op when unconfigured, always exits 0).
- `plugin.json` version is `0.4.0` and a matching root-`CHANGELOG.md` autopilot entry exists.
- No umputun-referenced files are modified.

## Context (from discovery)

- Files/components involved:
  - `plugins/autopilot/.claude-plugin/plugin.json` — version `0.3.1` → `0.4.0`; new `telegram_control` userConfig.
  - `plugins/autopilot/skills/batch/SKILL.md` — orchestrator (281 lines). Step 3 = worktree question; Step 4 = context capture (`PROJECT`/`BRANCH`); Step 6 = queue loop (substeps 1–7); Telegram Notifications section.
  - `plugins/autopilot/skills/batch/scripts/notify.sh` — one-way sender; token/chat/topic resolution lives in lines 49–121.
  - `plugins/autopilot/skills/batch/scripts/poll-commands.sh` — **new**.
  - `plugins/autopilot/skills/batch/scripts/_tg-resolve.sh` — **new** shared resolution helper.
  - `plugins/autopilot/references/telegram-setup.md` — operator setup docs.
  - `plugins/autopilot/README.md` — userConfig table, Telegram section, Known limitations.
  - `CHANGELOG.md` (root) — autopilot section.
- Related patterns found:
  - `notify.sh` is invoked as `notify.sh "${CLAUDE_PLUGIN_DATA}" "<msg>"` — data dir passed explicitly as `$1` because `$CLAUDE_PLUGIN_DATA` is not reliably exported into Bash subprocesses. `poll-commands.sh` must follow the same calling convention.
  - The credential/routing resolution (env → `telegram.conf` → sibling `autopilot-*` fallback → topic map by normalized `git remote origin`) is non-trivial and currently inline in `notify.sh`.
  - `planning:exec` (umputun, referenced via git-subdir — **must not be edited**) always asks a worktree question in its Step 2 and states "Auto mode does NOT exempt this question." autopilot cannot suppress or programmatically answer it.
- Dependencies identified:
  - Shared helper `_tg-resolve.sh` is consumed by both `notify.sh` (refactor) and `poll-commands.sh` (new).
  - bats unit tests for these scripts are owned by the **infra/quality plan** (`20260606-infra-quality-ci.md`). This plan verifies scripts via `shellcheck` + manual smoke runs; the infra plan adds the formal bats suite. **Run this plan (A) before the infra plan (B)** so B's bats can cover the scripts created here.

## Development Approach

- **Testing approach**: Regular (code first, then tests). For shell utilities with external
  effects (git, curl/getUpdates), each task verifies via `shellcheck` clean + a documented
  manual smoke invocation asserting expected stdout/exit. Formal bats unit tests are added
  in the infra/quality plan (B), which centralizes the test harness.
- Complete each task fully before the next; small, focused changes.
- **CRITICAL**: never edit umputun-referenced plugins (`planning`, etc.). Only `plugins/autopilot/**` and root docs are in scope.
- **CRITICAL**: `notify.sh` must remain backward-compatible (same CLI, same fire-and-forget exit-0 behavior) after the refactor — the queue calls it as a no-op when unconfigured.
- Bump version + CHANGELOG per repo convention (CLAUDE.md).

## Testing Strategy

- **unit tests**: shell-level. This plan uses `shellcheck` + manual smoke runs per task.
- **⚠️ Stated coverage risk**: within v0.4 itself, the highest-logic-density new script
  (`poll-commands.sh`: offset persistence, JSON filtering, date cutoff, command parsing) is
  covered only by `shellcheck` + a stubbed-`getUpdates` smoke run. Formal automated coverage
  is **mandatory** in the infra plan (B), whose bats suite for `_tg-resolve.sh` and
  `poll-commands.sh` is non-optional and which **hard-depends on this plan landing first**.
  We accept manual-smoke-only inside A by design (bats harness is bootstrapped in B); B must
  not ship without these tests.
- **e2e tests**: none (no UI; live Telegram delivery is manually smoke-tested by the operator).

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- keep plan in sync with actual work

## Solution Overview

- **Worktree hint**: autopilot's model is unchanged (Step 3 AskUserQuestion + `EnterWorktree`
  stay). A new banner is printed inside the Step 6 loop, right before invoking
  `/planning:exec`, keyed by the chosen worktree strategy `WT`.
- **Two-way control**: a best-effort poller (`poll-commands.sh`) reads new Telegram messages
  via `getUpdates` with a persisted offset, filters to the configured chat/topic (+ optional
  user allowlist) and to messages newer than queue start, and prints recognized commands.
  The orchestrator checks at the top of each loop iteration and acts (`stop` → graceful halt;
  `status` → reply). Gated behind opt-in `telegram_control`.

## Technical Details

- **`_tg-resolve.sh`** (sourced, not executed): given `$1 = data_dir`, resolves and exports
  `TG_TOKEN`, `TG_CHAT`, `TG_TOPIC`, `TG_LABEL`, `TG_DATA_DIR` (the dir the conf was found
  in, for sibling-fallback consistency with the topics map), and `TG_ALLOWED`
  (`TELEGRAM_ALLOWED_USER_IDS`, resolved from env/conf alongside the others so the allowlist
  flows through the same path as every other routing value — not env-only). Returns non-zero
  (or leaves `TG_TOKEN`/`TG_CHAT` empty) when unconfigured. Encapsulates: env seed →
  `telegram.conf` → sibling `autopilot-*` search → fill blanks → topic lookup by normalized
  origin remote.
- **`poll-commands.sh <data-dir> <queue-start-epoch>`**: sources `_tg-resolve.sh`; if
  unconfigured → `exit 0` silently. Reads offset from `<TG_DATA_DIR>/telegram-offset`
  (per-chat keyed file). Calls `getUpdates?offset=<o>&timeout=0&allowed_updates=["message"]`
  (`--max-time 10`). For each update: keep only `message.chat.id == TG_CHAT`, and if
  `TG_TOPIC` set then `message.message_thread_id == TG_TOPIC`, and if
  `TELEGRAM_ALLOWED_USER_IDS` set then `message.from.id ∈` list, and `message.date ≥`
  queue-start-epoch. Map text (`/stop`, `/stop@bot`, bare `stop`; same for `status`) to a
  normalized token printed one-per-line. Persist `offset = max(update_id)+1`. Always `exit 0`.
  Parse JSON with `jq`. Note: Step 6's substeps are numbered 1–7 in the current SKILL.md
  (not 6.1–6.7); the two additions below are described by position, not literal numbers.
- **SKILL.md Step 6 wiring**:
  - **Poll checkpoint** — a new FIRST substep, before the existing substep 1 ("Announce"):
    only when `telegram_control != false`, run `poll-commands.sh "${CLAUDE_PLUGIN_DATA}" "$QSTART"`.
    On `stop`: send ack `🛑 <PROJECT> [<BRANCH>] — stopped by command`, set
    `skipped += (M - N + 1)`, break to Step 7. On `status`: send
    `📊 <PROJECT> [N/M] — ok:<c> fail:<f> skip:<s>` via `notify.sh`, continue.
  - **Worktree hint** — a new substep between the worktree pre-arrange (substep 4) and the
    `/planning:exec` invoke (substep 5), printed just before the invoke:
    `per_plan` → "autopilot already isolated this plan in its own worktree — when /planning:exec asks about isolation, choose **Stay here**." `shared` → "running in the shared queue worktree — choose **Stay here**." `none` → "autopilot is running in-place; answer /planning:exec's isolation question as you prefer."
  - Step 4 also captures `QSTART=$(date +%s)` once, next to `PROJECT`/`BRANCH`.
- **plugin.json**: add `telegram_control` (boolean, default `false`).

## What Goes Where

- **Implementation Steps** (`[ ]`): all script, SKILL.md, plugin.json, and doc changes.
- **Post-Completion** (no checkboxes): live Telegram smoke test from a phone; deciding
  whether to also expose `/skip`/`/abort` in a future version.

## Implementation Steps

### Task 1: Extract shared Telegram resolution helper + refactor notify.sh

**Files:**
- Create: `plugins/autopilot/skills/batch/scripts/_tg-resolve.sh`
- Modify: `plugins/autopilot/skills/batch/scripts/notify.sh`

- [ ] create `_tg-resolve.sh` containing the resolution logic currently in `notify.sh` lines 49–121 (data-dir resolution, env seed, conf pick + sibling `autopilot-*` fallback, fill-blanks, topic lookup by normalized origin), exporting `TG_TOKEN`/`TG_CHAT`/`TG_TOPIC`/`TG_LABEL`/`TG_DATA_DIR`
- [ ] refactor `notify.sh` to `source` the helper and use the exported vars for its send step; preserve exact CLI (`notify.sh <data-dir> <msg...>`), plain-text send, and always-`exit 0` behavior
- [ ] guard the helper for safe sourcing (no `exit`; signal "unconfigured" by empty `TG_TOKEN`/`TG_CHAT`) and add `# shellcheck shell=bash` / disable directives as needed
- [ ] verify: `shellcheck _tg-resolve.sh notify.sh` is clean
- [ ] smoke test: with no conf, `notify.sh "" "x"` exits 0 silently; with a temp `telegram.conf` fixture, sourcing the helper exports the expected vars (manual run) — must pass before Task 2

### Task 2: Add poll-commands.sh (getUpdates → /stop, /status)

**Files:**
- Create: `plugins/autopilot/skills/batch/scripts/poll-commands.sh`

- [ ] create `poll-commands.sh <data-dir> <queue-start-epoch>` sourcing `_tg-resolve.sh`; `exit 0` silently when unconfigured
- [ ] implement offset persistence in `<TG_DATA_DIR>/telegram-offset` and the `getUpdates?offset=&timeout=0&allowed_updates=["message"]` call (`--max-time 10`), parsing with `jq`
- [ ] implement filtering (chat id, optional topic, optional `TG_ALLOWED` allowlist from the helper, `date ≥ queue-start-epoch`) and map `/stop`,`/status` (incl. `@bot` and bare forms) to normalized tokens printed one-per-line; always `exit 0`
- [ ] verify: `shellcheck poll-commands.sh` is clean
- [ ] smoke test: unconfigured → no output, exit 0; with a stubbed `getUpdates` JSON fixture (via a `CURL`/PATH shim or `--data` capture), assert `/stop` and `/status` are recognized and stale-dated messages are dropped — must pass before Task 3

### Task 3: Worktree hint banner in the queue loop

**Files:**
- Modify: `plugins/autopilot/skills/batch/SKILL.md`

- [ ] add a new substep between worktree pre-arrange (substep 4) and the `/planning:exec` invoke (substep 5) instructing the orchestrator to print a deterministic worktree hint, with the three strategy-keyed messages (`per_plan`/`shared` → "choose Stay here"; `none` → neutral) — these are the **canonical** hint strings
- [ ] explain in-line WHY (planning:exec always asks; cannot be suppressed from loom; hint trivializes the second prompt) referencing the no-drift constraint
- [ ] verify: SKILL.md still parses as a valid skill (front-matter intact); the three canonical hint strings are defined here (Task 5 will mirror them verbatim in the README, and the verbatim cross-check is performed in Task 7)
- [ ] verify: the hint substep is positioned before the `/planning:exec` invoke — must pass before Task 4

### Task 4: Two-way control wiring + telegram_control config

**Files:**
- Modify: `plugins/autopilot/skills/batch/SKILL.md`
- Modify: `plugins/autopilot/.claude-plugin/plugin.json`

- [ ] in SKILL.md Step 4, capture `QSTART=$(date +%s)` once alongside `PROJECT`/`BRANCH`
- [ ] in SKILL.md Step 6, add a new FIRST substep (before "Announce") — poll checkpoint, gated by `telegram_control != false`: handle `stop` (ack + `skipped += M-N+1` + break to Step 7) and `status` (send counters via `notify.sh`, continue); document the plan-boundary-only limitation inline
- [ ] add `telegram_control` (boolean, default `false`) to `plugin.json` userConfig with a description noting it is opt-in and changes control flow
- [ ] verify: `plugin.json` is valid JSON (`jq . plugin.json`) and `version` is bumped to `0.4.0`
- [ ] smoke test: walk the SKILL.md control flow on paper for stop/status/none-configured paths; assert no path can block the queue (poll failure → continue) — must pass before Task 5

### Task 5: Documentation — README, telegram-setup, CHANGELOG, version

**Files:**
- Modify: `plugins/autopilot/README.md`
- Modify: `plugins/autopilot/references/telegram-setup.md`
- Modify: `CHANGELOG.md`
- Modify: `plugins/autopilot/.claude-plugin/plugin.json`
- Modify: `CLAUDE.md` (only if a new convention emerged)

- [ ] README: add `telegram_control` to the userConfig table; document `/stop` & `/status`, the optional `TELEGRAM_ALLOWED_USER_IDS`, and the worktree-hint behavior; mirror the three canonical worktree-hint strings (from Task 3) verbatim in the Known-limitations note; update Known limitations (plan-boundary control only; planning:exec prompt cannot be removed from loom)
- [ ] README: update the Structure section to list `poll-commands.sh` and `_tg-resolve.sh`
- [ ] telegram-setup.md: add a "Two-way control" section (enable `telegram_control`, set `TELEGRAM_ALLOWED_USER_IDS`, supported commands, latency caveat)
- [ ] confirm `plugin.json` `version` = `0.4.0`
- [ ] CHANGELOG.md: add an autopilot `0.4.0 — 2026-06-06` entry (worktree hint; two-way Telegram `/stop`+`/status`; `telegram_control` config; `_tg-resolve.sh` extraction). NOTE: the root CHANGELOG header-scope fix (adding `slicer`) is owned by plan B (`20260606-infra-quality-ci.md`) — do NOT touch the header scope line here
- [ ] CLAUDE.md: add a one-line convention only if one emerged (e.g. "shared TG resolution lives in `_tg-resolve.sh`"); otherwise skip
- [ ] verify: English-primary prose (per CLAUDE.md); links resolve; entry wording matches plugin.json — must pass before Task 6

### Task 6: Verify acceptance criteria

- [ ] verify every Acceptance Criteria item (top of plan) is met
- [ ] verbatim cross-check: the three worktree-hint strings in SKILL.md (Task 3) match the README Known-limitations note (Task 5)
- [ ] run `shellcheck` on `_tg-resolve.sh`, `notify.sh`, `poll-commands.sh` — clean
- [ ] run `jq . plugins/autopilot/.claude-plugin/plugin.json` — valid; `version == 0.4.0`
- [ ] confirm `notify.sh` unchanged-behavior smoke (unconfigured = silent exit 0) still holds after refactor
- [ ] confirm no umputun-referenced files were touched (`git status` shows only `plugins/autopilot/**`, `CHANGELOG.md`, `CLAUDE.md`, `docs/plans/**`) — must pass before Task 7

### Task 7: Finalize

- [ ] move this plan to `docs/plans/completed/` (skip if executed via autopilot — it auto-moves on success)

## Post-Completion

**Manual verification:**
- Live phone smoke test: enable `telegram_control`, run a 2-plan queue, send `/status` mid-run (between plans) and `/stop`; confirm acks and that the queue halts gracefully and a re-run resumes from filesystem state.

**Future considerations (not in scope):**
- Optional `/skip` and `/abort` commands.
- Upstream proposal to umputun for a non-interactive `worktree_mode` in `planning:exec` (the only path to zero worktree prompts).
