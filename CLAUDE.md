# CLAUDE.md — loom marketplace

Agent contract for this repo. Personal Claude Code plugin marketplace: 3 own
plugins (`autopilot`, `kit`, `slicer`) + 7 plugins referenced from
`umputun/cc-thingz`. Follows the **universal** half of
[llm-kit](https://github.com/g-agent-lab/llm-kit) (`UNIVERSAL_CORE.md` §5/§6/§7);
the TS architecture-enforcement half does not apply (see
[`docs/reference/architecture-exemptions.md`](docs/reference/architecture-exemptions.md)).

## 1. Language

Reply to the operator in their language (they write in Russian). Public-facing
prose (README, plugin READMEs, manifest descriptions) is **English-primary**;
Russian appears only inside skill `description` trigger lists.

## 2. Entry point

Read [`docs/CONTEXT.md`](docs/CONTEXT.md) first. Doc rules live in
[`docs/DOCS_RULES.md`](docs/DOCS_RULES.md); where things are, in `docs/reference/`.

## 3. Default context boundary

Do **not** read by default: `docs/plans/active/completed/`, `docs/archive/`,
`docs/changelog/`. Read `docs/SESSION.md` for the live session log.

## 4. Architecture invariants

- **Own plugins only.** Edit `plugins/{autopilot,kit,slicer}/`. The umputun
  plugins are referenced via `git-subdir` in
  [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) and must
  stay references — no copies, no edits, no drift (`drift-guard.sh` enforces).
- **Manifest is the source of truth** for what the marketplace exposes. Add/
  remove umputun plugins by editing the `git-subdir` entries; never hand-edit
  Claude Code's internal `~/.claude/plugins/*.json` state. How-to:
  [`docs/operations/marketplace-management.md`](docs/operations/marketplace-management.md).
- **`slicer` is the single source of truth** for `slice-draft-to-plans` — do not
  re-add a copy to llm-kit's bootstrap templates.
- **Versioning.** Any change to an own plugin bumps `version` in its
  `.claude-plugin/plugin.json` **and** adds a `CHANGELOG.md` entry.
  `version-sync.sh` fails the build (diff-aware) on an unchanged/downgraded
  version or a bump without a matching changelog line.
- **Bilingual triggers.** Skill `description` fields list English phrases first,
  then Russian. Slash-command identifiers stay Latin (`/autopilot:run`, `/kit:init`).

## 5. Required validation (before pushing)

Run from the repo root (so the root `.shellcheckrc` is honored):

```
bash scripts/validate-marketplace.sh && bash scripts/drift-guard.sh \
  && bash scripts/version-sync.sh && bash scripts/link-check.sh \
  && bash scripts/docs-lint.sh
shellcheck $(git ls-files '*.sh')
bats tests/
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) re-runs all of these
on every push/PR. See the README's "Development / CI" section.

## 6. Stack

Markdown + shell (`bash`/`jq`) + JSON manifests; bats tests; GitHub Actions CI.
No app build, no module graph — `kit`'s stack detection returns `unknown`, so
only the universal docs discipline applies. Sibling component: **`loom-relay`**
(separate repo) — a TypeScript Cloudflare Worker serving `autopilot`'s two-way
Telegram control (`/stop` · `/status`) over a CF-Access-gated MCP server.

## 7. External access / secrets

No credentials in this repo. Telegram bot token and chat/topic ids live in the
per-machine plugin data dir (`telegram.conf` / `telegram-topics.conf`); Cloudflare
Access service tokens live on the machine and in `loom-relay`. See
[`docs/reference/env-variables.md`](docs/reference/env-variables.md) and
[`docs/reference/contracts.md`](docs/reference/contracts.md).

## 8. Skills / reference

Details that aren't always-on live in `docs/reference/` and
[`docs/operations/`](docs/operations/marketplace-management.md). llm-kit canon:
[`g-agent-lab/llm-kit`](https://github.com/g-agent-lab/llm-kit).
