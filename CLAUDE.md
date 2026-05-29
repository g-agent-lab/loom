# CLAUDE.md — loom marketplace

Personal Claude Code plugin marketplace. Two own plugins (`autopilot`, `kit`) plus
seven plugins referenced from `umputun/cc-thingz`.

## Conventions

- **Own plugins only.** Edit `plugins/autopilot/` and `plugins/kit/`. Never vendor
  or edit umputun's plugins here — they are referenced via `git-subdir` in
  `.claude-plugin/marketplace.json` and must stay references (no copies, no drift).
- **Versioning.** Bump `version` in the plugin's `.claude-plugin/plugin.json` and add
  a `CHANGELOG.md` entry for any change to an own plugin.
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
