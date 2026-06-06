# autopilot v0.4.0 — worktree hint + two-way control via loom-relay (MCP)

## Overview

Two operator-facing improvements to the `autopilot` plugin, shipped together as **v0.4.0**:

1. **Worktree hint ("Own + hint").** autopilot keeps owning worktree isolation, but prints a
   deterministic guidance banner before each `/planning:exec` call so the operator knows how to
   answer `planning:exec`'s own (unavoidable) isolation question. Trivializes the second of the
   two worktree prompts per plan.
2. **Two-way control via the `loom-relay` MCP hub.** A new opt-in `relay_control` mode lets the
   operator send `/stop` (graceful halt after the current plan) and `/status` (reply with live
   counters) from Telegram. **autopilot no longer touches Telegram for intake** — it calls the
   relay's MCP tools at plan boundaries. This replaces the abandoned in-plugin polling design
   (see why below). Commands are checked at **plan boundaries only** — no mid-plan interruption.

> **This plan was redesigned.** An earlier draft polled Telegram `getUpdates` from inside the
> plugin (`poll-commands.sh`). Deep research proved that unsound for a shared multi-machine bot:
> the `getUpdates` offset is **bot-wide per token**, caps at 100 unconfirmed updates, and allows
> **only one consumer per token** (409). The intake now lives in the separate **`loom-relay`**
> Cloudflare Worker (see `01-loom-relay-hub.md`), which owns the webhook and exposes
> `poll_commands` / `post_status` MCP tools. **`loom-relay` must be built/deployed and its MCP
> server configured in the session before this plan's Feature 2 is usable.**

Problem solved: the queue double-asks about worktrees, and was one-way only. This adds reliable
remote control without forking the upstream `planning` plugin and without the polling pitfalls.

## Acceptance Criteria

- The worktree hint banner is printed before every `/planning:exec` invoke, with the correct
  string for each strategy (`per_plan`, `shared`, `none`); `WT` is normalized to that enum.
- With `relay_control == true` AND the relay MCP server connected: `/stop` halts the queue
  gracefully after the current plan (remaining → skipped, Telegram reply via `post_status`, durable
  ack via `ack_commands`); `/status` replies with live counters and does not change control flow.
- With `relay_control` off OR the MCP server not connected: the boundary checkpoint is a silent
  no-op; the queue behaves exactly as v0.3.1.
- Relay calls use `RELAY_PROJECT_KEY` (normalized `git remote origin`, matching `notify.sh`), NOT
  the display `PROJECT` basename; and the `.mcp.json` server name is required to be exactly
  `loom-relay` so the static `allowed-tools` entries resolve (a name mismatch is a silent no-op).
- `notify.sh` (one-way progress notifications) is **unchanged** and keeps working (sendMessage is
  unaffected by the relay's webhook).
- `plugin.json` version is `0.4.0` with a matching root-`CHANGELOG.md` autopilot entry.
- No umputun-referenced files are modified; no Telegram bot token is added to the repo.

## Context (from discovery)

- Files/components involved:
  - `plugins/autopilot/.claude-plugin/plugin.json` — `0.3.1` → `0.4.0`; new `relay_control` userConfig.
  - `plugins/autopilot/skills/batch/SKILL.md` — orchestrator (281 lines). Step 3 = worktree
    question (stores `WT` as the AskUserQuestion **label**); Step 4 = context capture
    (`PROJECT`/`BRANCH`); Step 6 = queue loop (substeps 1–7); `allowed-tools` front-matter.
  - `plugins/autopilot/skills/batch/scripts/notify.sh` — one-way sender, **unchanged** by this plan.
  - `plugins/autopilot/references/telegram-setup.md` + a new `references/relay-control.md`.
  - `plugins/autopilot/README.md`, `CHANGELOG.md` (root).
- Related patterns / constraints:
  - `planning:exec` (umputun, git-subdir — **must not be edited**) always asks a worktree
    question (its Step 2: "Auto mode does NOT exempt this question"). autopilot cannot suppress
    or programmatically answer it → hence the hint (Feature 1).
  - The relay `project` key = normalized `git remote origin` (same normalization `notify.sh`
    already does), captured into a **distinct `RELAY_PROJECT_KEY`** variable. It is **NOT** the
    existing `PROJECT` (repo *basename*, `SKILL.md:71`, used only for display in notify messages);
    reusing `PROJECT` for the relay would not match the relay's `PROJECT_ROUTES` key and would
    silently poll the wrong queue.
  - **No new shell scripts.** Because intake moved to the relay, there is no `poll-commands.sh`,
    and the previously-planned `_tg-resolve.sh` extraction is dropped (YAGNI: `notify.sh` would be
    its only consumer). `notify.sh` stays as-is.
- Dependencies:
  - **Hard dependency on `01-loom-relay-hub.md`** (the MCP hub) for Feature 2 at runtime.
    The hub's tool contract: `poll_commands(project, since, ack_through)` returns commands with
    `id > ack_through` and `ts >= since` (ascending `id`); `ack_commands(project, ack_through)`
    advances the cursor without returning (used to confirm a handled batch when there's no next
    poll — e.g. before `/stop`/final exit); `post_status(project, text)`. `id` = Telegram
    `update_id`, `ts` = `message.date` (epoch sec).
  - The MCP server is configured per-machine in `.mcp.json`, authenticating to Cloudflare Access
    by sending `CF-Access-Client-Id` / `CF-Access-Client-Secret` (Access **service-token**)
    headers via `${...}` env-expansion (never committed — NOT a single bearer token; the Worker
    verifies only the Access-injected assertion). autopilot does not configure it — it just uses it.

## Development Approach

- **Testing approach**: Regular (code first, then tests). Feature 1 (worktree hint) and Feature 2
  (boundary MCP calls) are SKILL.md orchestration — verified by control-flow walkthroughs +
  `jq` validity of `plugin.json`; Feature 2's end-to-end is an integration smoke against a local
  `loom-relay` (`wrangler dev`). No new shell scripts → nothing new for the infra plan's bats.
- Complete each task fully; small, focused changes.
- **CRITICAL**: never edit umputun-referenced plugins. Only `plugins/autopilot/**` + root docs.
- **CRITICAL**: `notify.sh` is not touched; progress notifications keep working.
- Bump version + CHANGELOG per repo convention (CLAUDE.md).

## Testing Strategy

- **unit/flow**: SKILL.md control-flow walkthrough for the stop / status / not-configured paths
  (assert no path can block the queue — MCP call failure → no-op continue); `jq` validity for
  `plugin.json`.
- **integration smoke** (manual / Post-Completion): with a local `loom-relay` via `wrangler dev`
  and the MCP server configured, run a 2-plan queue, send `/status` then `/stop`, confirm reply +
  graceful halt.
- **e2e**: none.

## Progress Tracking

- mark `[x]` immediately when done; ➕ for new tasks; ⚠️ for blockers; keep in sync.

## Solution Overview

- **Worktree hint**: autopilot's model unchanged (Step 3 AskUserQuestion + `EnterWorktree` stay).
  After Step 3, normalize `WT` (label → enum). A banner is printed inside the Step 6 loop right
  before invoking `/planning:exec`, keyed by the canonical enum.
- **Two-way control**: at the top of each Step 6 iteration, when `relay_control == true` and the
  relay MCP tools are available, the orchestrator calls `poll_commands(project=RELAY_PROJECT_KEY,
  since=QSTART, ack_through=LAST_HANDLED_ID)`, then acts: `stop` → graceful halt; `status` →
  `post_status` reply with counters. Durable ack of handled commands is via `ack_commands`, NOT
  `post_status` (which only sends the Telegram reply). The relay (single Telegram consumer)
  handles webhook intake, dedup, allowlist, and topic→project demux — autopilot only consumes its
  own project's queue. One **final checkpoint** runs after the last plan (before the summary) so a
  command sent during the last plan — notably `/status` — is still answered and acked.

## Technical Details

- **SKILL.md front-matter**: add the relay MCP tools to `allowed-tools`:
  `mcp__loom-relay__poll_commands`, `mcp__loom-relay__ack_commands`, `mcp__loom-relay__post_status`.
  These names are **static in the packaged skill**, so the MCP server name in `.mcp.json` is a
  **hard contract: it MUST be exactly `loom-relay`**. A different server name yields
  `mcp__<other>__*` tools that are absent from `allowed-tools`, so the calls never resolve — and
  because the design treats an unavailable tool as a silent no-op, `relay_control=true` would then
  **silently do nothing** (indistinguishable from "not configured"). This is a documented
  requirement in `relay-control.md` and the relay's `SETUP.md`, NOT an "assumption". (A SKILL.md
  cannot itself detect a name mismatch vs. genuine non-configuration — both surface as tool-absent
  — so the name requirement is enforced by docs, and the silent-no-op caveat is called out so the
  operator knows where to look.)
- **Step 3 → normalize `WT`**: map the stored AskUserQuestion label (`Worktree per plan` / `One
  shared worktree` / `In-place`) — or the `worktree_strategy` userConfig — to ONE canonical enum
  (`per_plan`/`shared`/`none`). Both worktree pre-arrange (substep 4) and the hint switch on it.
- **Step 4**: capture `QSTART=$(date +%s)` once, alongside `PROJECT`/`BRANCH`. **Also capture a
  distinct `RELAY_PROJECT_KEY`** — the **normalized `git remote origin`** computed with the EXACT
  same steps as `notify.sh` (drop trailing `.git`, drop `scheme://`, drop `user@`, scp
  `host:path` → `host/path`, lowercase; fall back to repo basename only if there is no origin).
  This is the `project` argument for every relay tool call. **Do NOT reuse `PROJECT`** — that is
  the repo *basename* (`SKILL.md:71`, display-only) and will not match the relay's
  `PROJECT_ROUTES` key (normalized origin), so `poll_commands`/`post_status` would silently target
  the wrong (empty) queue. Track an in-memory `LAST_HANDLED_ID` for `ack_through`, **initialized to
  the integer `0`** (NOT empty): `ack_through` is a numeric cursor — `id <= 0` drops nothing and
  `id > 0` returns everything, so `0` is the correct "nothing acked yet" start. An empty/unset
  value would fail the relay tool's input-schema validation → MCP error → the first poll silently
  no-ops (and stays broken until a command is handled, i.e. never).
- **Step 6 substeps** (numbered 1–7 today; additions described by position):
  - **Poll checkpoint** — new FIRST substep, before "Announce": only when `relay_control == true`
    (strict — opt-in, default `false`; anything other than an explicit `true`, incl.
    absent/unparsed config, leaves the path OFF) AND the relay MCP tools are available, call
    `poll_commands(project=RELAY_PROJECT_KEY, since=QSTART, ack_through=LAST_HANDLED_ID)`. Process
    returned commands in ascending `id`, performing each effect FIRST — note `post_status` only
    sends the Telegram **reply**, it is NOT the durable ack (that is `ack_commands`): `status` →
    `post_status(project=RELAY_PROJECT_KEY, "📊 [N/M] ok:<c> fail:<f> skip:<s>")`; `stop` →
    `post_status(project=RELAY_PROJECT_KEY, "🛑 stopped by command")`, set
    `skipped += (M - N + 1)`, mark the queue to break to Step 7. **Durably acknowledge only AFTER
    an effect succeeds**: advance `LAST_HANDLED_ID` to that command's `id`, then call
    `ack_commands(project=RELAY_PROJECT_KEY, ack_through=LAST_HANDLED_ID)` as the LAST relay call (for `stop`, ack
    *then* break). A command whose effect fails (e.g. `post_status` errored) is NOT acked → it
    stays in the relay for retry next poll (true at-least-once). Any MCP error or unavailable
    server → **no-op, continue** (never blocks the queue).
  - **Worktree hint** — new substep between worktree pre-arrange (4) and the `/planning:exec`
    invoke (5): `per_plan` → "autopilot already isolated this plan in its own worktree — when
    /planning:exec asks about isolation, choose **Stay here**." `shared` → "running in the shared
    queue worktree — choose **Stay here**." `none` → "autopilot is running in-place; answer
    /planning:exec's isolation question as you prefer." (canonical strings)
  - **Final checkpoint** — runs ONCE after the loop exits (all plans done OR a `stop` break),
    before the Step 7 summary, under the same `relay_control == true` + tools-available gating.
    Do ONE last `poll_commands(project=RELAY_PROJECT_KEY, since=QSTART, ack_through=LAST_HANDLED_ID)`
    so a command sent **during the last plan** is still handled: a late `status` →
    `post_status(project=RELAY_PROJECT_KEY, …)` reply with final counters; a late `stop` is a
    **no-op** (the queue is already ending — do not double-count `skipped`). Then advance
    `LAST_HANDLED_ID` and `ack_commands(project=RELAY_PROJECT_KEY, ack_through=LAST_HANDLED_ID)` —
    **this is exactly the terminal case `ack_commands` exists for**: there is no next poll to ride
    the ack on. Any MCP error/unavailable → no-op (never blocks the summary).
- **plugin.json**: add `relay_control` (boolean, default `false`; opt-in, changes control flow).

## What Goes Where

- **Implementation Steps** (`[ ]`): SKILL.md, plugin.json, and doc changes.
- **Post-Completion** (no checkboxes): deploy/configure `loom-relay` + the `.mcp.json` MCP server;
  live phone smoke; deciding whether to expose `/skip`/`/abort` later.

## Implementation Steps

### Task 1: Worktree hint banner + WT normalization (Feature 1)

**Files:**
- Modify: `plugins/autopilot/skills/batch/SKILL.md`

- [ ] add a normalization step right after Step 3's AskUserQuestion: map the stored `WT` label (`Worktree per plan`/`One shared worktree`/`In-place`) or the `worktree_strategy` userConfig to ONE canonical enum (`per_plan`/`shared`/`none`); both pre-arrange (substep 4) and the hint switch on it
- [ ] add a substep between worktree pre-arrange (4) and the `/planning:exec` invoke (5) printing the deterministic hint keyed by the canonical enum — these are the **canonical** hint strings
- [ ] explain in-line WHY (planning:exec always asks; cannot be suppressed from loom; no-drift)
- [ ] verify: SKILL.md front-matter intact; hint substep positioned before the invoke; the three canonical strings are defined here (mirrored in README in Task 4, cross-checked in Task 5)
- [ ] run a control-flow walkthrough for all three strategies — must pass before Task 2

### Task 2: Two-way control via relay MCP (Feature 2)

**Files:**
- Modify: `plugins/autopilot/skills/batch/SKILL.md`

- [ ] add the relay MCP tools to the SKILL `allowed-tools` front-matter; **require** the `.mcp.json` server name to be exactly `loom-relay` (static tool names ⇒ a mismatched name makes `relay_control` a silent no-op) — state this requirement, do not leave it as an assumption
- [ ] Step 4: capture `QSTART=$(date +%s)` once (next to `PROJECT`/`BRANCH`), capture `RELAY_PROJECT_KEY` = normalized `git remote origin` (EXACT same normalization as `notify.sh`, NOT the `PROJECT` basename — a mismatch silently polls the wrong relay queue), and init `LAST_HANDLED_ID=0` (numeric cursor — empty/unset fails the relay tool schema and no-ops the poll)
- [ ] Step 6: add a FIRST substep (before "Announce") — when `relay_control == true` (strict; default `false`, anything not explicitly `true` stays OFF) and the relay MCP tools are available, call `poll_commands(project=RELAY_PROJECT_KEY, since=QSTART, ack_through=LAST_HANDLED_ID)`; process commands in ascending `id`, performing each effect FIRST — `post_status` is only the Telegram **reply**, NOT the durable ack (`status` → `post_status(project=RELAY_PROJECT_KEY, …)` counters reply; `stop` → `post_status(project=RELAY_PROJECT_KEY, …)` reply + `skipped += M-N+1` + mark break); ONLY after an effect succeeds advance `LAST_HANDLED_ID` to its `id`, then durably ack via `ack_commands(project=RELAY_PROJECT_KEY, ack_through=LAST_HANDLED_ID)` as the LAST relay call (for `stop`, ack then break to Step 7); a failed effect is not acked (retries next poll); ANY MCP error/unavailable → no-op continue
- [ ] add a FINAL checkpoint after the loop exits (before Step 7 summary): one last `poll_commands(project=RELAY_PROJECT_KEY, …)` so a command sent during the last plan is still handled (`status` → `post_status` reply with final counters; a late `stop` is a no-op — don't double-count `skipped`), then `ack_commands(project=RELAY_PROJECT_KEY, …)` the handled ids (terminal case — no next poll); same gating; MCP error → no-op
- [ ] document inline: plan-boundary-only control (no mid-plan), and that intake/dedup/allowlist/demux live in `loom-relay` (not here)
- [ ] run a control-flow walkthrough: stop, status, relay-off, MCP-unavailable, AND a command arriving during the last plan (final checkpoint answers it) all behave (no path blocks the queue) — must pass before Task 3

### Task 3: relay_control userConfig + version bump

**Files:**
- Modify: `plugins/autopilot/.claude-plugin/plugin.json`

- [ ] add `relay_control` (boolean, default `false`) to userConfig with a description: opt-in, requires the `loom-relay` MCP server configured, changes control flow
- [ ] bump `version` to `0.4.0`
- [ ] verify: `jq . plugins/autopilot/.claude-plugin/plugin.json` is valid; `version == 0.4.0` — must pass before Task 4

### Task 4: Documentation — README, relay-control ref, CHANGELOG

**Files:**
- Modify: `plugins/autopilot/README.md`
- Create: `plugins/autopilot/references/relay-control.md`
- Modify: `CHANGELOG.md`

- [ ] README: add `relay_control` to the userConfig table; document two-way control via `loom-relay` (`/stop`,`/status`), the `.mcp.json` setup sending `CF-Access-Client-Id`/`CF-Access-Client-Secret` (Access service-token) headers via `${...}` env-expansion (no secret in repo), and the worktree-hint behavior; mirror the three canonical hint strings verbatim in Known limitations; update Known limitations (plan-boundary control only; planning:exec prompt cannot be removed from loom; intake lives in loom-relay)
- [ ] `references/relay-control.md`: how to point autopilot at a deployed `loom-relay` (MCP server entry in `.mcp.json` — **the entry MUST be named exactly `loom-relay`**, since a different name silently disables control — with the CF Access service-token headers `CF-Access-Client-Id`/`CF-Access-Client-Secret` via env, supported commands, latency caveat); cross-link `01-loom-relay-hub.md`
- [ ] CHANGELOG.md: add an autopilot `0.4.0 — 2026-06-06` entry (worktree hint; two-way control via loom-relay MCP `/stop`+`/status`; `relay_control` config). NOTE: the root CHANGELOG header-scope fix (adding `slicer`) is owned by plan B — do NOT touch the header scope here
- [ ] verify: English-primary prose; links resolve; no bot token / secret in any doc — must pass before Task 5

### Task 5: Verify acceptance criteria

- [ ] verify every Acceptance Criteria item (top of plan) is met
- [ ] verbatim cross-check: the three worktree-hint strings in SKILL.md (Task 1) match the README Known-limitations note (Task 4)
- [ ] `jq . plugins/autopilot/.claude-plugin/plugin.json` — valid; `version == 0.4.0`
- [ ] confirm `notify.sh` is untouched (progress notifications still work)
- [ ] confirm no umputun-referenced files changed and no secret added (`git status` shows only `plugins/autopilot/**`, `CHANGELOG.md`, `docs/plans/**`) — must pass before Task 6

### Task 6: Finalize

- [ ] move this plan to `docs/plans/completed/` (skip if executed via autopilot — it auto-moves on success)

## Post-Completion

*Requires external systems — no checkboxes.*

**Dependency (separate plan):** `loom-relay` (`01-loom-relay-hub.md`) must be implemented
and deployed, and its MCP server added to the machine's `.mcp.json`, before Feature 2 works
end-to-end. Until then, `relay_control` off (default) = v0.3.1 behavior.

**Manual verification:** with `loom-relay` deployed + MCP configured, enable `relay_control`, run
a 2-plan queue, send `/status` and `/stop` from Telegram; confirm reply + graceful halt + that a
re-run resumes from filesystem state.

**Future (not in scope):** optional `/skip`,`/abort`; upstream `worktree_mode` proposal to umputun
for `planning:exec` (the only path to zero worktree prompts).
