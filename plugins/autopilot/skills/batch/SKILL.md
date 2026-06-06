---
name: batch
description: "Run a queue of plan files sequentially and autonomously via /planning:exec, each in its own git worktree. Use when the user says 'autopilot', 'run all plans', 'process the queue', 'batch exec', 'run plans one after another', or has multiple plan files in docs/plans/active/ to execute back-to-back. Также срабатывает на русские фразы: «автопилот», «прогони все планы», «запусти очередь планов», «прогон планов по очереди», «прогони планы автопилотом»."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash:*), Skill, AskUserQuestion, TaskCreate, TaskUpdate, EnterWorktree, mcp__loom-relay__poll_commands, mcp__loom-relay__ack_commands, mcp__loom-relay__post_status
---

# batch

Execute multiple plan files sequentially. For each discovered plan: spawn `/planning:exec` via the Skill tool; after it returns, verify all `### Task N:` (or `### Iteration N:`) checkboxes are `[x]`; if yes, move the plan to `completed/` and continue with the next plan; if no, follow the `stop_on_failure` userConfig policy.

You are the QUEUE ORCHESTRATOR. You do NOT execute plan tasks yourself. You do NOT read code, write code, debug, or investigate. All execution work happens inside `/planning:exec`. Your role is strictly: discover plans → loop → invoke `/planning:exec` → verify outcome by re-reading the plan file → move successful plans → report progress.

## Arguments

- `$ARGUMENTS` — optional directory path containing plans (relative to project root). When empty or absent, fall back to the `plans_dir` userConfig (default: `docs/plans/active`).

## Custom Rules Loading

Before starting, run this command via Bash tool to check for user-provided custom rules:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh queue-rules.md ${CLAUDE_PLUGIN_DATA}
```

If the output is non-empty, treat it as additional instructions that supplement (not replace) the rules below. Apply throughout the queue run. See `${CLAUDE_PLUGIN_ROOT}/references/custom-rules.md` for full documentation.

### Rules Management

When the user asks to add, show, or clear custom queue rules:

- **show rules**: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh queue-rules.md ${CLAUDE_PLUGIN_DATA}` and display the output. If empty, tell the user no custom rules are configured.
- **add/update project rules**: write content to `.claude/queue-rules.md` in the current working directory.
- **add/update user rules**: check `$CLAUDE_PLUGIN_DATA`; if set, write to `$CLAUDE_PLUGIN_DATA/queue-rules.md`; if not set, tell the user user-level rules require marketplace install and offer project-level instead.
- **clear**: delete the corresponding file.

Project-level rules take precedence. **CRITICAL: this skill must NEVER modify its own files** (SKILL.md, scripts, plugin.json, references). Only `.claude/queue-rules.md` and `$CLAUDE_PLUGIN_DATA/queue-rules.md` are writable for rules management.

## Telegram Notifications

The queue can push progress to Telegram so the operator sees plan-by-plan status without watching the session. This is **opt-in and best-effort**: it never blocks, retries, or fails a queue run.

**Gating.** Notifications are active only when the `notify` userConfig is not `false` (default `true`). If `notify` is `false`, skip every notification step below entirely and run the queue silently. When `notify` is on but no credentials are configured, the script is a silent no-op — so it is always safe to call.

**Setup (operator, one-time).** No Telegram id ever lives in a repo. The notify script reads everything from env or from per-machine files in `$CLAUDE_PLUGIN_DATA`:

```
# $CLAUDE_PLUGIN_DATA/telegram.conf  (secret; per machine)
TELEGRAM_BOT_TOKEN=123456:AA...
TELEGRAM_CHAT_ID=-1001234567890        # supergroup id (one, shared across projects)
TELEGRAM_LABEL=home                    # optional machine tag (home/work)

# $CLAUDE_PLUGIN_DATA/telegram-topics.conf  (project -> forum topic; per machine)
github.com/me/proj-a = 42              # key = normalized `git remote origin`
```

When the user asks to set up notifications and `$CLAUDE_PLUGIN_DATA` is set, write these files for them (chat/topic ids come from messaging the bot, then opening `https://api.telegram.org/bot<token>/getUpdates`). If `$CLAUDE_PLUGIN_DATA` is unset, tell them to export the env vars instead. See `${CLAUDE_PLUGIN_ROOT}/references/telegram-setup.md`.

**Multi-machine / topics / label are handled entirely inside `notify.sh`** — it routes each project to its forum topic (via `message_thread_id`, looked up from the topic map by the repo's `origin` remote) and prepends the machine label. The orchestrator does NOT build these in: just send the plain `<PROJECT> [<BRANCH>]`-prefixed text below and the script adds the rest. Two machines posting to the same bot never collide — `sendMessage` only appends.

**Sending.** All messages go through one helper. Pass the plugin data dir as the **first** argument (exactly as the custom-rules call passes it to `resolve-rules.sh`) and the full message text as the second — `$CLAUDE_PLUGIN_DATA` is NOT reliably present inside a Bash subprocess, so it must be threaded in via the placeholder, not left to the env var:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/notify.sh "${CLAUDE_PLUGIN_DATA}" "<message text>"
```

Always keep `"${CLAUDE_PLUGIN_DATA}"` quoted so an empty value stays a single (empty) positional argument rather than swallowing the message. If the dir resolves to the "wrong" install sibling (`autopilot-inline` vs `autopilot-loom`), `notify.sh` falls back to searching every `autopilot-*` data dir for a configured token, so a credential placed in either sibling still delivers.

**Context.** At queue start (Step 4) capture, once, the project name and branch for message prefixes:

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"); BRANCH=$(git branch --show-current 2>/dev/null); echo "$PROJECT [$BRANCH]"
```

Reuse `<PROJECT>` and `<BRANCH>` in every message below.

**Level.** The `notify_level` userConfig (default `per_plan`) controls volume:
- `per_plan` — send all five event types below.
- `summary` — send only **queue start**, **plan failure**, and **final summary** (skip per-plan start and per-plan success messages).

**Events and templates** (plain text; emoji are intentional):

| Event | Level | Step | Template |
|---|---|---|---|
| Queue start | always | 4 | `🚀 <PROJECT> [<BRANCH>] — queue: <M> plan(s)` + newline + numbered plan-basename list |
| Plan start | per_plan only | 6.1 | `▶️ <PROJECT> [N/M] <plan-basename> — running` |
| Plan success | per_plan only | 6.7 | `✅ <PROJECT> [N/M] <plan-basename> — done → <completed-subdir>/` (append ` (already complete)` when it was complete on entry) |
| Plan failure | always | 6.7 | `❌ <PROJECT> [N/M] <plan-basename> — FAILED (<count> tasks unchecked)` |
| Final summary | always | 8 | `🏁 <PROJECT> [<BRANCH>] — done: <completed> ok, <failed> failed, <skipped> skipped` |

Failures are sent at **both** levels — a failure is exactly the moment the operator needs to know. Treat each `notify.sh` call as fire-and-forget: do not check its output, do not retry, do not let it affect queue control flow.

## Two-way control via loom-relay

Remote control activates **automatically whenever the `loom-relay` MCP server is connected** — i.e. its `poll_commands` / `ack_commands` / `post_status` tools are available. **There is no separate toggle to set**: configuring the `loom-relay` MCP server *is* the opt-in, and removing it (`claude mcp remove loom-relay`) is the opt-out. (This replaced the old `relay_control` userConfig, which Claude Code only let you flip in the interactive `/plugin` UI — un-scriptable.) With the server connected, the operator can send `/stop` (graceful halt after the current plan) and `/status` (live counters reply) from Telegram. Commands are checked at **plan boundaries only** — never mid-plan.

**autopilot does NOT touch Telegram for intake.** Webhook ownership, dedup, allowlist, and topic→project demux all live in the separate **`loom-relay`** Cloudflare Worker (see `01-loom-relay-hub.md`). autopilot is just an MCP client that, at each boundary, polls **its own project's** queue and replies. `notify.sh` (one-way progress) is independent and unaffected — `sendMessage` still works with the relay's webhook set.

**Hard requirement — the MCP server MUST be named exactly `loom-relay`.** The `allowed-tools` front-matter lists `mcp__loom-relay__poll_commands` / `…__ack_commands` / `…__post_status` *statically*. A `.mcp.json` server under any other name yields `mcp__<other>__*` tools that are absent from `allowed-tools`, so the calls never resolve — and because an unavailable tool is treated as a silent no-op, control would then **silently do nothing**, indistinguishable from "not configured". The skill cannot tell a name mismatch from genuine non-configuration (both surface as tool-absent), so this is a **documented requirement**, not an assumption — and the silent-no-op is called out so you know where to look. The server authenticates to Cloudflare Access with **service-token** headers (`CF-Access-Client-Id` / `CF-Access-Client-Secret`) supplied to the `.mcp.json` entry via a `headersHelper` script (recommended — it reads the token from a local file, so control connects regardless of how Claude Code was launched) or via `${...}` env-expansion; the secret is never committed. Setup: `${CLAUDE_PLUGIN_ROOT}/references/relay-control.md`.

**Project key.** Every relay call uses `RELAY_PROJECT_KEY` — the **normalized `git remote origin`** (the exact same normalization `notify.sh` does), captured in Step 4. This is NOT the display `PROJECT` basename; reusing `PROJECT` would not match the relay's `PROJECT_ROUTES` key and would silently poll the wrong (empty) queue.

**Ack semantics.** `post_status` only sends the Telegram **reply** — it is NOT the durable ack. Durably acknowledging a handled command is `ack_commands(project, ack_through)`, called as the LAST relay call after an effect has succeeded. A command whose effect fails is NOT acked → it stays in the relay for retry on the next poll (true at-least-once).

**Never blocks the queue.** Any MCP error, input-schema rejection, or unavailable server → **no-op, continue**. The control path can never stall, fail, or block a run.

## Process

### Step 1. Resolve plans directory

If `$ARGUMENTS` is a non-empty string, use it as the plans directory. Otherwise, use the `plans_dir` userConfig value (default: `docs/plans/active`). Resolve relative paths against the current working directory.

Report the resolved directory to the user: "Queue dir: `<path>`"

### Step 2. Discover plans

Run the discovery script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/discover-plans.sh <plans-dir>
```

The script outputs one plan file path per line, lexicographically sorted, excluding any `completed/` subdirectory. Plans without at least one `### Task N:` or `### Iteration N:` heading are skipped (they aren't runnable plans).

If the output is empty:
- Report "Queue is empty — no runnable plans found in `<plans-dir>`."
- STOP. Do not proceed to subsequent steps.

If the output is non-empty:
- Count the discovered plans as `M`.
- If the `max_plans_per_run` userConfig is greater than 0 and `M` exceeds it, truncate to `max_plans_per_run` and tell the user: "Discovered M plans; capping at K per `max_plans_per_run`."
- Report the discovered list to the user as a numbered list, one plan per line.

### Step 3. Confirm worktree strategy

Read the `worktree_strategy` userConfig (default: `per_plan`). Then **always** confirm with the user via AskUserQuestion before starting the loop — the choice affects every plan in the queue and the orchestrator cannot decide on the user's behalf.

Invoke AskUserQuestion with:

```json
{
  "questions": [{
    "question": "How should the queue isolate plans?",
    "header": "Isolation",
    "options": [
      {"label": "Worktree per plan", "description": "Create a new isolated git worktree for each plan. Most defensive — plans cannot interfere with each other. Each plan ends as a separate feature branch in its own worktree."},
      {"label": "One shared worktree", "description": "Create one isolated worktree for the whole queue; all plans execute within it. Saves filesystem space but cross-plan side effects are possible."},
      {"label": "In-place (no worktree)", "description": "Run all plans in the current working directory. No isolation. Fastest, but a failed plan can leave the working tree in an unclean state."}
    ],
    "multiSelect": false
  }]
}
```

Default the focused option to whatever the userConfig is set to. Store the answer as `WT`.

**Normalize `WT` to a canonical enum.** The AskUserQuestion answer is stored as the option **label**. Map it — or the `worktree_strategy` userConfig, when the answer is the default — to ONE canonical strategy enum, and use that enum everywhere downstream (both the Step 6 worktree pre-arrange and the worktree hint switch on it):

| Stored label / `worktree_strategy` | Canonical `WT` |
|---|---|
| `Worktree per plan` / `per_plan` | `per_plan` |
| `One shared worktree` / `shared` | `shared` |
| `In-place (no worktree)` / `none` | `none` |

### Step 4. Initialize queue log

Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/init-queue-log.sh /tmp/queue-$(date +%Y%m%d-%H%M%S).log <plans-dir> <M> <WT>
```

Capture the log path it outputs (after the leading `queue-log:` prefix). Use this path for all subsequent `append-queue-log.sh` calls. Report the log path to the user.

IMPORTANT: Always use `${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/append-queue-log.sh` to write to the log after initialization. Never write to it directly.

**Capture two-way-control context (only when the `loom-relay` MCP tools are available — see Two-way control).** Once, alongside `PROJECT`/`BRANCH`, capture the queue start time, the relay project key, and the ack cursor:

```bash
QSTART=$(date +%s); LAST_HANDLED_ID=0
key="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$key" ]; then
  key="${key%.git}"; key="${key#*://}"; key="${key#*@}"; key="${key/:/\/}"
else
  key="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
fi
RELAY_PROJECT_KEY="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"; echo "$RELAY_PROJECT_KEY"
```

`RELAY_PROJECT_KEY` matches `notify.sh`'s normalization exactly (NOT the `PROJECT` basename). `LAST_HANDLED_ID` is the numeric `ack_through` cursor — it MUST start at the integer `0` (not empty/unset): `id <= 0` acks nothing and `id > 0` returns everything, so `0` is the correct "nothing handled yet" start; an empty value would fail the relay tool's input schema → MCP error → the first poll silently no-ops.

**Notify (if `notify` is on — see Telegram Notifications).** Capture `<PROJECT>` and `<BRANCH>` once (the context snippet in that section), then send the **queue start** message: `🚀 <PROJECT> [<BRANCH>] — queue: <M> plan(s)` followed by a newline and the numbered list of plan basenames. Pass the whole thing as the **message** (second) argument to `notify.sh`, with `"${CLAUDE_PLUGIN_DATA}"` as the first — see the Sending block above.

### Step 5. Create TaskCreate items

Create one TaskCreate per discovered plan in order:

- `TaskCreate(subject="Queue: <plan-basename>", description="Run /planning:exec on <plan-path>", activeForm="Running <plan-basename>...")`

Then add two final tasks:

- `TaskCreate(subject="Queue summary", description="Aggregate per-plan outcomes", activeForm="Summarizing queue results...")`

Remember the taskIds in the order plans were discovered, so Step 6 can update them.

### Step 6. The queue loop

Initialize counters: `completed=0`, `failed=0`, `skipped=0`. Iterate over the discovered plans in order, tracking the current 1-based index `N` and the total `M`.

For each plan:

**Boundary control checkpoint** (runs FIRST, before substep 1 below — only when the `loom-relay` MCP tools are available; otherwise skip entirely, a silent no-op). Call `poll_commands(project=RELAY_PROJECT_KEY, since=QSTART, ack_through=LAST_HANDLED_ID)`. Process returned commands in **ascending `id`**; for each, perform its effect FIRST, then durably ack:
- `status` → `post_status(project=RELAY_PROJECT_KEY, "📊 [N/M] ok:<completed> fail:<failed> skip:<skipped>")`. Reply only — does NOT change control flow.
- `stop` → `post_status(project=RELAY_PROJECT_KEY, "🛑 stopped by command")`, then `skipped += (M - N + 1)` (plan N has not run yet, so it and all remaining are skipped) and mark the queue to break to Step 7 after this checkpoint finishes.
- **Durably ack only AFTER an effect succeeds**: advance `LAST_HANDLED_ID` to that command's `id`, then call `ack_commands(project=RELAY_PROJECT_KEY, ack_through=LAST_HANDLED_ID)` as the LAST relay call (for `stop`: ack, then break). A command whose effect failed (e.g. `post_status` errored) is NOT acked — it stays in the relay and retries on the next poll.
- ANY MCP error or unavailable server → **no-op, continue** (never blocks the queue).

1. **Announce** to the user with a banner:

   ```
   --- Queue plan N of M: <plan-basename> ---
   ```

2. **Mark task in_progress**: `TaskUpdate(taskId, status="in_progress")`. **Notify (per_plan level only):** `▶️ <PROJECT> [N/M] <plan-basename> — running`.

3. **Pre-flight: idempotent success check (NEW in v0.2)**. Re-read the plan file from disk. Count:
   - Total `### Task N:` and `### Iteration N:` sections containing checkboxes.
   - Sections where ALL checkbox items are `[x]` (no `[ ]` remaining within that section).

   If every Task/Iteration section is already at zero `[ ]` items (the plan is fully complete on entry — typically because a prior session already finished it):
   - Report to the user: `↻ Plan N of M: <plan-basename> already complete on entry (X tasks, 0 unchecked). Skipping /planning:exec and treating as success.`
   - Skip directly to **step 7 (Handle outcome → success path)** below. Do NOT create a worktree (steps 4-5), do NOT invoke `/planning:exec` (step 6), do NOT do further verification.

   CRITICAL: an already-complete plan is **success**, not "nothing to do" and not failure. The queue's job is to advance the file system from `active/` to `completed/`; if work was already done in a prior session, the queue still owns the move.

4. **Pre-arrange the worktree** according to the canonical `WT` enum (only reached when the plan is NOT already complete):
   - `per_plan`: derive a branch slug from the plan filename (strip leading `NN-` or `yyyymmdd-` prefix and `.md` suffix, lowercase, replace non-alphanumeric with `-`). Use the `EnterWorktree` tool to create a fresh worktree on that branch. If `EnterWorktree` errors because the worktree already exists at the target path (leftover from a prior aborted queue run for the same plan), reuse the existing worktree instead — enter it and proceed.
   - `shared`: only on the **first** iteration, create a worktree under branch `cc-queue-shared`. On subsequent iterations, do nothing — we are already inside the shared worktree.
   - `none`: do nothing.

   **Worktree hint** (print after pre-arranging, immediately before invoking `/planning:exec` in substep 5). `/planning:exec`'s own Step 2 ALWAYS asks an isolation question — auto mode does not exempt it, and loom cannot suppress or pre-answer it from here — so print a deterministic hint keyed by the canonical `WT` enum, so the operator answers without guesswork. These are the **canonical** hint strings (mirrored verbatim in README Known limitations):
   - `per_plan` → `↳ autopilot already isolated this plan in its own worktree — when /planning:exec asks about isolation, choose **Stay here**.`
   - `shared` → `↳ running in the shared queue worktree — when /planning:exec asks about isolation, choose **Stay here**.`
   - `none` → `↳ autopilot is running in-place; answer /planning:exec's isolation question as you prefer.`

5. **Invoke `/planning:exec`** via the Skill tool. Set `skill` to `"planning:exec"` and `args` to the absolute path of the current plan file. **Do NOT** pass it the plans directory — pass the single plan file.

6. **After the Skill call returns**, re-read the plan file from disk and re-count checkboxes (same logic as step 3).

   Define the plan as **successful** if and only if every Task/Iteration section has zero `[ ]` items. The plan is **failed** otherwise.

7. **Handle outcome**. This step runs UNCONDITIONALLY at the end of every per-plan iteration, regardless of whether the plan was already complete on entry (step 3) or completed via `/planning:exec` invocation (steps 4-6). The path is chosen by the success/failure flag from step 3 or step 6.

   On success (plan has zero `[ ]` items remaining — whether already so on entry or completed by /planning:exec):
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/mark-completed.sh <plan-path> <completed-subdir>` (use the `completed_subdir` userConfig). The script moves the plan into the `completed/` subdirectory. **This is mandatory** — the queue owns the active→completed move and MUST execute it on success, even when no /planning:exec invocation happened in this iteration.
   - Increment `completed`.
   - Append to queue log: `bash ${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/append-queue-log.sh <log-path> "ok <plan-basename>"`. When the plan was already complete on entry, append `"ok <plan-basename> (already complete)"` instead.
   - `TaskUpdate(taskId, status="completed")`.
   - Report to user: `✓ Plan N of M: <plan-basename> completed (moved to <completed-subdir>/)`.
   - **Notify (per_plan level only):** `✅ <PROJECT> [N/M] <plan-basename> — done → <completed-subdir>/` (append ` (already complete)` when it was complete on entry).
   - Continue to the next plan.

   On failure:
   - DO NOT move the plan.
   - Increment `failed`.
   - Append to log: `bash ${CLAUDE_PLUGIN_ROOT}/skills/batch/scripts/append-queue-log.sh <log-path> "fail <plan-basename>: <count> tasks unchecked"`.
   - `TaskUpdate(taskId, status="completed")` (it's done from the queue's perspective — it ran).
   - Report to user: `✗ Plan N of M: <plan-basename> stopped with unchecked tasks`.
   - **Notify (always, both levels):** `❌ <PROJECT> [N/M] <plan-basename> — FAILED (<count> tasks unchecked)`.
   - Check the `stop_on_failure` userConfig (default: true):
     - If true: increment `skipped` by the number of remaining plans (`M - N`). Break out of the loop and proceed to Step 7.
     - If false: continue to the next plan.

CRITICAL: The ONLY way the queue knows a plan succeeded is by re-reading the file and counting `[ ]`. Never trust the Skill tool return text alone — `/planning:exec` reports completion but does not move the plan, so the file is your ground truth.

CRITICAL: You are the QUEUE ORCHESTRATOR. Do NOT investigate why a plan failed. Do NOT read source code, run tests, or fix issues yourself. If a plan fails, log it, follow `stop_on_failure`, and either continue or stop. Failure investigation is the user's job after the queue finishes.

CRITICAL: Do NOT modify the plan file yourself. Only `/planning:exec` (via its subagents) writes to the plan. The `mark-completed.sh` script only moves the file; it does not edit content.

Safety: bound the loop at most `M` iterations. The loop's only termination conditions are (a) all M plans processed, (b) a failure with `stop_on_failure=true`, or (c) a `/stop` at the boundary checkpoint (when the `loom-relay` MCP is connected).

**Final boundary checkpoint** (runs ONCE after the loop exits — whether all plans completed, a failure broke it, or a `/stop` broke it — before the Step 7 summary; same tools-available gating). Do one last `poll_commands(project=RELAY_PROJECT_KEY, since=QSTART, ack_through=LAST_HANDLED_ID)` so a command sent **during the last plan** is still handled:
- a late `status` → `post_status(project=RELAY_PROJECT_KEY, …)` reply with the final counters;
- a late `stop` is a **no-op** (the queue is already ending — do NOT double-count `skipped`).
Then advance `LAST_HANDLED_ID` and `ack_commands(project=RELAY_PROJECT_KEY, ack_through=LAST_HANDLED_ID)` the handled ids — this is exactly the terminal case `ack_commands` exists for (there is no next poll to ride the ack on). Any MCP error/unavailable → no-op (never blocks the summary).

### Step 7. Queue summary

After the loop ends (naturally or via stop_on_failure), update the summary task:

- `TaskUpdate(summaryTaskId, status="in_progress")`

Build a compact summary block:

```
=== Queue summary ===
completed: <completed>
failed:    <failed>
skipped:   <skipped>
total:     M
log:       <log-path>

per-plan:
  ✓ <plan-basename-1>
  ✓ <plan-basename-2>
  ✗ <plan-basename-3>     (X tasks unchecked)
  ⊘ <plan-basename-4>     (skipped — earlier failure)
  ⊘ <plan-basename-5>     (skipped — earlier failure)
```

Show this block to the user verbatim. Append the same block to the queue log via append-queue-log.sh.

`TaskUpdate(summaryTaskId, status="completed")`.

### Step 8. Completion

Report a single final line:

```
Queue done: <completed> completed, <failed> failed, <skipped> skipped.
```

**Notify (always, when `notify` is on):** send the **final summary** message: `🏁 <PROJECT> [<BRANCH>] — done: <completed> ok, <failed> failed, <skipped> skipped`.

Do not push branches, do not merge worktrees, do not delete worktrees. The user inspects the resulting branches and decides what to merge or discard. The queue's job ends here.

## Key Rules

- Each plan runs through `/planning:exec` (the planning plugin's autonomous executor). Queue does NOT reimplement task loops, reviews, or finalize.
- The plan file is the single source of truth for success/failure. Always re-read it from disk.
- Plans without at least one `### Task N:` or `### Iteration N:` heading are not runnable and are skipped at discovery.
- The `completed_subdir` is created lazily by `mark-completed.sh` only on first successful move.
- No automatic merging — the user always reviews resulting feature branches manually.
- No background processes, no daemons. The queue runs entirely inside this Claude Code session.
- If the session ends mid-queue, re-running `/autopilot:run` resumes naturally: completed plans are already in `completed/` and are not re-discovered.
