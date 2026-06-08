# ROADMAP — loom marketplace

> Where we are, what's in progress, what's next. Compact by design (~100 lines).
> Lifecycle and rules: [`../DOCS_RULES.md`](../DOCS_RULES.md).

## Где мы / Where we are

A published plugin marketplace: 3 own plugins (`autopilot`, `kit`, `slicer`) +
7 umputun plugins by reference. Full CI (validate-marketplace, drift-guard,
version-sync, link-check, shellcheck, bats, docs-lint). Two-way Telegram control
for `autopilot` is served by the deployed sibling `loom-relay` Worker. The repo
now follows the llm-kit universal documentation discipline.

## В работе / In progress

- _(none)_

## Что дальше / Next

- **loom-relay dedicated CI.** The relay (network-facing, holds secrets) has 34
  passing vitest tests but no CI gate of its own. Add a minimal GitHub Actions
  `vitest run` + the `typescript-node-cli` llm-kit overlay (the stack-specific
  half that genuinely applies there). _(separate repo)_
- **"Superseded" banner on `plans/active/completed/02-autopilot-v0.4.md`.** v0.5.0 removed
  `relay_control` one commit after the plan completed, so the historical plan
  contradicts the shipped code. Add a top-of-file pointer to CHANGELOG/SKILL.md.
- **Fix the `PROJECT_ROUTES` note in `plans/active/completed/01-loom-relay-hub.md`.** It
  pins it as a "plain JSON var"; it shipped as a secret.

## Сделано / Done

- llm-kit universal-core docs discipline applied (2026-06-08).
- `03-infra-quality-ci` — check scripts, bats suite, GitHub Actions CI
  ([plan](completed/03-infra-quality-ci.md)).
- `02-autopilot-v0.4` then v0.5.0 — worktree hint + two-way control via
  loom-relay; `relay_control` toggle later removed in favor of MCP-presence
  auto-activation ([plan](completed/02-autopilot-v0.4.md)).
- `01-loom-relay-hub` — Cloudflare Worker hub built and deployed
  ([plan](completed/01-loom-relay-hub.md)).
- autopilot Telegram notifications (v0.3.x).
- Initial marketplace: autopilot + kit, umputun plugins by reference.
