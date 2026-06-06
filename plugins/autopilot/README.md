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
| `notify` | `true` | Telegram notifications master switch (no-op until configured) |
| `notify_level` | `per_plan` | `per_plan` \| `summary` |

Two-way control (`/stop`, `/status`) has **no userConfig** — it turns on by itself
when the `loom-relay` MCP server is connected. See below.

## Telegram notifications

Opt-in. Start a queue and watch it from your phone — queue start, each plan,
failures, and the final summary, each tagged with machine, project, branch, `N/M`:

```
🏠 home: 🚀 my-app [main] — queue: 4 plan(s)
🏠 home: ▶️ my-app [2/4] 02-api.md — running
🏠 home: ✅ my-app [2/4] 02-api.md — done → completed/
🏠 home: ❌ my-app [3/4] 03-ui.md — FAILED (3 tasks unchecked)
🏠 home: 🏁 my-app [main] — done: 3 ok, 1 failed, 0 skipped
```

Built for **one shared bot across several machines**: both post to one supergroup
with no collision (`sendMessage` only appends), each project routes to its own
**forum topic**, and a machine label (`home`/`work`) tells them apart. All Telegram
ids live in `$CLAUDE_PLUGIN_DATA` (never committed — only the bot token is a real
secret); unconfigured = silent no-op; best-effort, never blocks a run. Covers the
queue only, not standalone `/planning:exec`. Full setup, incl. the project→topic
map: [`references/telegram-setup.md`](references/telegram-setup.md).

## Two-way control (`/stop`, `/status`)

Active automatically whenever the `loom-relay` MCP server is connected — **no toggle**;
configuring the server is the opt-in, `claude mcp remove loom-relay` is the opt-out.
Control a running queue from Telegram: **`/stop`** halts the queue gracefully after the
current plan (remaining plans skipped); **`/status`** replies with live counters
(`ok` / `fail` / `skip`). Commands are checked at **plan boundaries only** — never mid-plan.

autopilot does **not** poll Telegram itself. Intake (webhook, dedup, allowlist,
topic→project routing) lives in a separate Cloudflare Worker, **`loom-relay`**,
which exposes `poll_commands` / `ack_commands` / `post_status` MCP tools. autopilot
calls them at each boundary for its own project's queue. One-way `notify.sh`
progress is unaffected and keeps working alongside it.

Setup: deploy `loom-relay`, then add it to the machine's `.mcp.json` **under exactly
the name `loom-relay`** (a different name silently disables control). Supply the
Cloudflare Access **service-token** headers with a `headersHelper` script — it reads
the token from a local file and emits the headers at connect time, so control works
**no matter how Claude Code was launched** and no secret lands in the config:

```jsonc
{
  "mcpServers": {
    "loom-relay": {
      "type": "http",
      "url": "https://relay.<your-domain>/mcp",
      "headersHelper": "bash /absolute/path/to/loom-relay-headers.sh"
    }
  }
}
```

The helper just prints the headers as JSON, e.g.
`{"CF-Access-Client-Id":"…","CF-Access-Client-Secret":"…"}`, reading them from a
local 600-mode file. (Simpler alternative: a static `headers` block using
`${LOOM_RELAY_CF_ACCESS_CLIENT_ID}` / `${LOOM_RELAY_CF_ACCESS_CLIENT_SECRET}`
env-expansion — but then those vars must be exported in the environment Claude Code
is launched from, which breaks if you launch from a stale terminal or a GUI.)

Full setup, supported commands, and the latency caveat:
[`references/relay-control.md`](references/relay-control.md).

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
│       ├── notify.sh                        # best-effort Telegram notifier
│       └── resolve-file.sh                  # override chain for prompts
├── references/
│   ├── usage.md
│   ├── custom-rules.md
│   ├── telegram-setup.md
│   └── relay-control.md                     # two-way control via loom-relay MCP
└── scripts/resolve-rules.sh                 # override chain for custom rules
```

## Known limitations

- `/planning:exec`'s worktree question is interactive and cannot be removed from loom (auto mode does not exempt it). Before each invoke, autopilot prints a deterministic hint keyed by the worktree strategy so you know how to answer — verbatim:
  - `per_plan` → `↳ autopilot already isolated this plan in its own worktree — when /planning:exec asks about isolation, choose **Stay here**.`
  - `shared` → `↳ running in the shared queue worktree — when /planning:exec asks about isolation, choose **Stay here**.`
  - `none` → `↳ autopilot is running in-place; answer /planning:exec's isolation question as you prefer.`
- Two-way control is **plan-boundary only** — `/stop` and `/status` are handled between plans, not mid-plan. Intake (webhook / dedup / allowlist / topic→project routing) lives in `loom-relay`, not here.
- Sessions are local. A run lasts until the session ends; restart picks up unfinished plans naturally via filesystem state.
- No parallel execution — by design.
- No multi-machine fleet view — each machine runs its own session.

## License

MIT.
