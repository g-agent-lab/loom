# autopilot

Sequential plan runner for [umputun/cc-thingz](https://github.com/umputun/cc-thingz)'s `planning` plugin.

Drop multiple plan files into `docs/plans/active/`. Run them one after another inside a single Claude Code interactive session.

```
/autopilot:run
```

For each plan: worktree → `/planning:exec` → verify all `[x]` → `mv` to `completed/` → next plan.

Single Claude Code session, subscription billing, no background daemons, no SDK credit pool.

## Why

`/planning:exec` (cc-thingz) runs one plan at a time. After it finishes one plan it stops; the user must manually start the next. `autopilot` adds the loop in the same style as cc-thingz: one slash command (`/autopilot:run`), one skill (`autopilot:batch`), userConfig, an override chain for custom prompts and rules, and TaskCreate progress integration.

The plan format is identical to `/planning:exec`'s: markdown with `### Task N:` (or `### Iteration N:`) level-3 headings and `[ ]` / `[x]` checkboxes. autopilot does not reimplement task execution or review — it delegates each plan entirely to `/planning:exec`.

## Install

Part of the [`g-agent-lab/loom`](https://github.com/g-agent-lab/loom) marketplace:

```
/plugin marketplace add g-agent-lab/loom
/plugin install autopilot@loom
```

Restart Claude Code to pick up the new commands and skill.

## Usage

```
/autopilot:run                       # discover from plans_dir userConfig (default docs/plans/active)
/autopilot:run docs/plans/wave-1     # discover from a specific directory
```

You can also just say it in natural language ("run all plans", «прогони все планы автопилотом») — the `batch` skill triggers on both English and Russian phrasings.

The skill asks once which worktree strategy to use across the run, then iterates.

## userConfig

| Key | Default | Purpose |
|---|---|---|
| `plans_dir` | `docs/plans/active` | Discovery root |
| `completed_subdir` | `completed` | Target subdir for successful plans |
| `stop_on_failure` | `true` | Break the run on first plan failure |
| `worktree_strategy` | `per_plan` | `per_plan` \| `shared` \| `none` |
| `max_plans_per_run` | `0` | Hard cap (0 = no cap) |

## Custom rules

Same convention as the cc-thingz planning plugin: write `.claude/queue-rules.md` (project) or `$CLAUDE_PLUGIN_DATA/queue-rules.md` (user). See `references/custom-rules.md` and the `Rules Management` section of `SKILL.md`.

## Structure

```
autopilot/
├── .claude-plugin/plugin.json
├── README.md
├── commands/run.md                          # /autopilot:run slash command (forwards to skill)
├── skills/batch/
│   ├── SKILL.md                             # the orchestrator
│   └── scripts/
│       ├── discover-plans.sh                # list runnable plans
│       ├── mark-completed.sh                # mv plan → completed/
│       ├── init-queue-log.sh
│       ├── append-queue-log.sh
│       └── resolve-file.sh                  # override chain for prompts
├── references/
│   ├── usage.md
│   └── custom-rules.md
└── scripts/resolve-rules.sh                 # override chain for custom rules
```

## Known limitations

- `/planning:exec` worktree question is interactive — the operator answers it once per plan.
- Sessions are local. A run lasts until the session ends; restart picks up unfinished plans naturally via filesystem state.
- No parallel execution — by design.
- No multi-machine fleet view — each machine runs its own session.

## License

MIT.
