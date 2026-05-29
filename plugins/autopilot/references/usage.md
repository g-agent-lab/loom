# autopilot — Usage

Sequential plan runner for [umputun/cc-thingz](https://github.com/umputun/cc-thingz)'s `planning` plugin. Drop multiple plan files into a directory, run them one after another autonomously inside a single Claude Code session.

## Why

`/planning:exec` runs ONE plan, multi-phase. It does not chain into the next plan. `autopilot` adds that loop, in the same style as cc-thingz: one slash command, one skill, custom rules, override chain, TaskCreate progress.

## Install

Part of the `g-agent-lab/loom` marketplace:

```
/plugin marketplace add g-agent-lab/loom
/plugin install autopilot@loom
```

Restart Claude Code to pick up the command and skill.

## Usage

After dropping plans in `docs/plans/active/` (or wherever `plans_dir` userConfig points):

```
/autopilot:run
```

Optional directory override:

```
/autopilot:run docs/plans/wave-1
```

The skill will:

1. Discover runnable plans (lexicographic, `### Task N:`-having files, no `completed/` files).
2. Ask once: worktree per plan / one shared worktree / in-place.
3. Loop: for each plan, set up worktree → invoke `/planning:exec <plan>` → re-read plan → if all `[x]`, `mv` to `completed/`; otherwise stop or continue per `stop_on_failure` userConfig.
4. Summarise: completed / failed / skipped + per-plan one-liners + log file path.

## Plan Format

Same as `/planning:exec`:

- Plan is a markdown file with `### Task N:` or `### Iteration N:` level-3 headings.
- Each task section has `[ ]` checkbox items, marked `[x]` by the executing subagent.
- All checkboxes `[x]` in every task section = success.
- Plan files in a `completed/` subdirectory are never re-discovered.

The queue does NOT inject a "move to completed" step into your plans — `mark-completed.sh` handles the move externally after `/planning:exec` returns successfully.

## userConfig

| Key | Default | Purpose |
|---|---|---|
| `plans_dir` | `docs/plans/active` | Discovery root |
| `completed_subdir` | `completed` | Target for `mv` after success |
| `stop_on_failure` | `true` | Break loop on first failure; otherwise continue |
| `worktree_strategy` | `per_plan` | `per_plan` \| `shared` \| `none` |
| `max_plans_per_run` | `0` | Hard cap on plans per invocation; 0 disables |
| `notify` | `true` | Telegram notifications master switch; no-op until credentials configured |
| `notify_level` | `per_plan` | `per_plan` (start + every plan + summary) \| `summary` (start + failures + summary) |

## Telegram notifications

Opt-in queue progress to a Telegram chat — queue start, per-plan start/result,
failures, final summary; each tagged with machine label, project, branch, and
`N/M`. Built for one shared bot across several machines: both post to one
supergroup with no collision, each project routes to its own forum topic
(`message_thread_id`), and a `TELEGRAM_LABEL` tells home/work apart. All ids live
in `$CLAUDE_PLUGIN_DATA` (`telegram.conf` + `telegram-topics.conf`) or env — never
committed; only the bot token is a real secret. Unconfigured = silent no-op;
best-effort, never blocks a run; covers the queue only. Full setup in
[`telegram-setup.md`](./telegram-setup.md).

## Custom rules

Project: `.claude/queue-rules.md`
User: `$CLAUDE_PLUGIN_DATA/queue-rules.md`

Project takes precedence. Resolution chain mirrors planning's `resolve-rules.sh`. See [`custom-rules.md`](./custom-rules.md) for the full mechanism.

Example rules:

```markdown
- Skip plans whose filename starts with `draft-`.
- After every 5 plans, prompt the user to confirm continuation.
- For failed plans, append the failure reason to `docs/plans/active/INBOX.md`.
```

(The skill applies rules as additional instructions; rules cannot bypass core safety checks like `stop_on_failure`.)

## Crash recovery

Queue keeps no internal state. Restart-safety comes from the filesystem:

- Completed plans live in `completed/` and are not re-discovered.
- A failed/in-progress plan stays in `active/` with its `[x]`/`[ ]` mix; re-running `/autopilot:run` finds it again. `/planning:exec` resumes from the first unchecked task on the next run.
- If a session dies during `/planning:exec`, the partially-committed branch remains; next `/autopilot:run` will create a fresh branch (or reuse via `create-branch.sh`) and continue from the unchecked tasks.

## Known limitations (v0.1)

- `/planning:exec` Step 2 (worktree question) is interactive and unavoidable per upstream — operator must answer it once per plan in the queue. Plan: send PR upstream adding `auto_worktree` userConfig; v0.2 of queue will pass that through.
- Single-session: queue dies when Claude Code session ends. Restart resumes from where we left off, but the running plan's `/planning:exec` may have to repeat its review phases. This is acceptable for personal use.
- No parallel execution. By design — operator's stated requirement is sequential.
- No cross-machine fleet view. Each machine runs its own queue in its own Claude Code session.
