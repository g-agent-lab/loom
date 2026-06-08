# Operations — marketplace management

> Operator runbook. Day-to-day install/update commands and how to add or remove
> a referenced plugin. Relocated here from `CLAUDE.md` to keep the contract lean.

## Install / update (operator)

```
/plugin marketplace add g-agent-lab/loom      # once per machine
/plugin install <name>@loom                    # per plugin
/plugin marketplace update                      # pull latest of everything
```

`/plugin marketplace update` pulls the latest of everything — own plugins from
this repo, umputun plugins from upstream.

## Adding an umputun plugin

Add a `git-subdir` entry to [`../../.claude-plugin/marketplace.json`](../../.claude-plugin/marketplace.json):

```json
{
  "name": "<plugin>",
  "source": { "source": "git-subdir", "url": "https://github.com/umputun/cc-thingz.git", "path": "plugins/<plugin>" },
  "description": "… (via umputun/cc-thingz)"
}
```

Omit `ref`/`sha` to track upstream's default branch. Pin a `sha` only to freeze a
specific upstream version. Then add the plugin to the README plugin table (keep it
at 3 own + 7 umputun = 10 rows). `validate-marketplace.sh` and `drift-guard.sh`
enforce the manifest shape.

## Removing a plugin

Delete its entry from the manifest and its README table row. Never hand-edit
Claude Code's internal `~/.claude/plugins/*.json` state — the manifest is the
single source of truth.

## Running the checks locally

See the README's [Development / CI](../../README.md) section for the full command
list (brew tooling, the five check scripts, `shellcheck`, `bats`, `docs-lint`).
