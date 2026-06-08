# CONTEXT — loom marketplace

> Entry point for an LLM entering this repo cold. Read this first, then
> [`../CLAUDE.md`](../CLAUDE.md) (the agent contract). Details live in
> [`reference/`](reference/) and [`DOCS_RULES.md`](DOCS_RULES.md).

## What this is

`loom` is a personal [Claude Code](https://docs.claude.com/en/docs/claude-code)
plugin **marketplace**. It is not an application — there is no build, no module
graph, no runtime. It is Markdown + shell (`bash`/`jq`) + JSON manifests, plus a
bats test suite and GitHub Actions CI.

It exposes **ten** plugins:

- **Three own** — `autopilot`, `kit`, `slicer` — edited here, in `plugins/<name>/`.
- **Seven from `umputun/cc-thingz`** — included **by reference** (`git-subdir` in
  [`../.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json)),
  never vendored or edited here.

## Sibling component (not in this repo)

`autopilot`'s two-way Telegram control (`/stop` · `/status`) is served by
**`loom-relay`** — a separate Cloudflare Worker repo (single webhook hub +
per-project, CF-Access-gated MCP relay). Deployed at `relay.gurgen.dev`. The
machine-side wiring lives in the `autopilot` plugin; see
[`plans/active/completed/01-loom-relay-hub.md`](plans/active/completed/01-loom-relay-hub.md)
and the relay repo's own `README.md` / `docs/SETUP.md`.

## Map — where things are

| Area | Path | Notes |
|---|---|---|
| Agent contract | [`../CLAUDE.md`](../CLAUDE.md) | 8-section contract, always loaded |
| Marketplace manifest | [`../.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) | source of truth for what's exposed |
| Own plugins | `../plugins/{autopilot,kit,slicer}/` | the only editable plugin code |
| Check scripts | `../scripts/*.sh` | CI guards (validate / drift / version-sync / link / docs-lint) |
| Tests | `../tests/*.bats` | bats unit tests for shell scripts |
| CI | [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml) | runs every check on push/PR |
| Docs rules | [`DOCS_RULES.md`](DOCS_RULES.md) | how `docs/` is kept honest |
| Roadmap | [`plans/ROADMAP.md`](plans/ROADMAP.md) | where we are / what's next |
| Reference | [`reference/`](reference/) | env vars, contracts, routing, exemptions |
| Operations | [`operations/`](operations/) | marketplace management runbook |

## Do not read by default

- `plans/active/completed/` — historical, completed plans (execution artifacts).
- `archive/` — retired material.
- `changelog/` — rotated session journal (read SESSION.md for the live one).

## Standard

This repo follows the **universal** half of [llm-kit](https://github.com/g-agent-lab/llm-kit)
(`UNIVERSAL_CORE.md` §5 documentation-as-memory, §6 CLAUDE.md contract, §7 plan
lifecycle). The **stack-specific** architecture-enforcement half (kind-based DAG,
dep-cruiser / boundary baselines, TS gates) does **not** apply — this is not a
TypeScript app. The deviations are recorded in
[`reference/architecture-exemptions.md`](reference/architecture-exemptions.md).
