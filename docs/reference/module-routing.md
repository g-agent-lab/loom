# Reference — module routing

> "Where do I put new logic?" The marketplace has no code module graph, so the
> zones below are by **directory role**, not by import layers.

## Zones

| Zone | Path | Editable? | Role |
|---|---|---|---|
| Own plugins | `plugins/{autopilot,kit,slicer}/` | ✅ yes | The product. All plugin behavior lives here. |
| umputun refs | `.claude-plugin/marketplace.json` (`git-subdir`) | ⚠️ by reference only | Add/remove via manifest entries; never vendor or edit the upstream files. |
| Check scripts | `scripts/*.sh` | ✅ yes | CI guards: validate-marketplace, drift-guard, version-sync, link-check, docs-lint. |
| Tests | `tests/*.bats`, `tests/helpers.bash` | ✅ yes | bats unit tests for the runtime shell scripts and the check scripts. |
| CI | `.github/workflows/ci.yml` | ✅ yes | Runs every check on push/PR. |
| Docs | `docs/` | ✅ yes | Per [`../DOCS_RULES.md`](../DOCS_RULES.md). |
| Root manifest/docs | `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `AGENTS.md`, `ATTRIBUTIONS.md` | ✅ yes | Public-facing; English-primary. |

## Decision table — where new logic goes

| You want to… | Put it in… | Then… |
|---|---|---|
| Change an own plugin's behavior | `plugins/<own>/...` | bump `plugin.json` `version` + add a `CHANGELOG.md` entry (version-sync enforces it) |
| Expose/remove an umputun plugin | `.claude-plugin/marketplace.json` | edit the `git-subdir` entry; update the README plugin table (10 rows) |
| Add a repo invariant guard | `scripts/<name>.sh` + `tests/<name>.bats` | wire it into `ci.yml`; keep it `bash`+`jq`+`grep`/`awk` only |
| Add a runtime shell script to a plugin | `plugins/<plugin>/.../scripts/` | add a bats test; read external config via documented env vars (see [`env-variables.md`](env-variables.md)) |
| Document a new env var | the script + [`env-variables.md`](env-variables.md) | docs-lint fails otherwise |
| Two-way Telegram control | the `loom-relay` sibling repo | this repo only consumes its MCP tools (see [`contracts.md`](contracts.md)) |

## Per-plugin docs

Each plugin's own `README.md` (`plugins/<name>/README.md`) **is** that module's
documentation — there is intentionally no `docs/modules/` (exemption #2 in
[`architecture-exemptions.md`](architecture-exemptions.md)).
