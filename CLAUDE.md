# CLAUDE.md — loom marketplace

Personal Claude Code plugin marketplace. Three own plugins (`autopilot`, `kit`,
`slicer`) plus seven plugins referenced from `umputun/cc-thingz`.

> **`autopilot` two-way Telegram control** (`/stop` · `/status`) lives in a **separate
> component**, not in this repo: **`loom-relay`** — a Cloudflare Worker (single webhook
> hub + per-project, CF-Access-gated MCP relay) in its own sibling repo. Machine-side
> MCP wiring is in the `autopilot` plugin (plan `02-autopilot-v0.4.md`).

## Conventions

- **Own plugins only.** Edit `plugins/autopilot/`, `plugins/kit/`, and `plugins/slicer/`.
  Never vendor or edit umputun's plugins here — they are referenced via `git-subdir` in
  `.claude-plugin/marketplace.json` and must stay references (no copies, no drift).
- **`slicer` is the single source of truth** for `slice-draft-to-plans`. The skill no
  longer ships in llm-kit's bootstrap templates — do not re-add a copy there.
- **Versioning.** Bump `version` in the plugin's `.claude-plugin/plugin.json` and add
  a `CHANGELOG.md` entry for any change to an own plugin (`autopilot`/`kit`/`slicer`).
  CI's `version-sync.sh` enforces this in diff-aware mode: a changed `plugins/<own>/**`
  file with an unchanged or downgraded `version`, or a bump without a matching changelog
  entry, FAILS the build.
- **Checks before pushing.** Run the check scripts (`scripts/validate-marketplace.sh`,
  `drift-guard.sh`, `version-sync.sh`, `link-check.sh`), `shellcheck $(git ls-files '*.sh')`,
  and `bats tests/` locally before pushing. CI (`.github/workflows/ci.yml`) re-runs all of
  them on every push/PR and enforces the drift, version-sync, and link guards. See the
  README's "Development / CI" section for the brew tooling and exact commands.
- **Bilingual triggers.** Skill `description` fields list English phrases first, then
  Russian phrases, for natural-language invocation in either language. Slash-command
  identifiers stay Latin (`/autopilot:run`, `/kit:init`).
- **Public-facing prose** (README, plugin READMEs, descriptions) is English-primary.
  Russian appears only inside skill trigger lists.
- **No manual marketplace.json drift.** The manifest is the source of truth for what
  this marketplace exposes. To add/remove umputun plugins, edit the `git-subdir`
  entries — do not hand-edit Claude Code's internal `~/.claude/plugins/*.json` state.

## Adding an umputun plugin

```json
{
  "name": "<plugin>",
  "source": { "source": "git-subdir", "url": "https://github.com/umputun/cc-thingz.git", "path": "plugins/<plugin>" },
  "description": "… (via umputun/cc-thingz)"
}
```

Omit `ref`/`sha` to track upstream's default branch. Pin a `sha` only if you need to
freeze a specific upstream version.

## Install / update (operator)

```
/plugin marketplace add g-agent-lab/loom      # once per machine
/plugin install <name>@loom                   # per plugin
/plugin marketplace update                    # pull latest of everything
```
