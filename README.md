# loom

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace.

Three plugins of my own — `autopilot`, `kit`, and `slicer` — plus the seven plugins from
[umputun/cc-thingz](https://github.com/umputun/cc-thingz), re-exposed **by reference**
(not copied) so they always track upstream.

## Install

```
/plugin marketplace add g-agent-lab/loom
```

Then install whatever you want:

```
/plugin install autopilot@loom
/plugin install kit@loom
/plugin install slicer@loom
/plugin install planning@loom
```

## Plugins

| Plugin | What it does | Origin |
|---|---|---|
| `autopilot` | Run a queue of plan files sequentially and autonomously via `/planning:exec`, each in its own git worktree | own |
| `kit` | Bootstrap [llm-kit](https://github.com/g-agent-lab/llm-kit) discipline (greenfield + brownfield) into any project | own |
| `slicer` | Slice a ready draft into ralphex-executable iteration plans — parser-strict, pack-split, sizing-checked | own |
| `brainstorm` | Collaborative design dialogue — idea → approaches → design → plan | umputun/cc-thingz |
| `planning` | Structured implementation planning + autonomous plan execution | umputun/cc-thingz |
| `review` | PR review, git diff annotation review, writing style guide | umputun/cc-thingz |
| `release-tools` | Release workflow — versioning, release notes, changelog | umputun/cc-thingz |
| `thinking-tools` | Dialectic, root-cause investigator, ask-codex | umputun/cc-thingz |
| `skill-eval` | Forces skill evaluation before every response | umputun/cc-thingz |
| `workflow` | Session helpers — learn, clarify, wrong, clipboard copy | umputun/cc-thingz |

## Related components

`autopilot`'s **two-way Telegram control** (`/stop` · `/status` during autonomous
runs) is served by **`loom-relay`** — a separate Cloudflare Worker (its own sibling
repo, not a plugin here). It is the single webhook-owning hub for the bot and relays
commands per project to machines over a remote, Cloudflare-Access-gated MCP server.
See `loom-relay/README.md` and `loom-relay/docs/SETUP.md`.

## How the umputun plugins are included

They are **not** vendored into this repo. Each is listed in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) with a `git-subdir`
source pointing at `umputun/cc-thingz`. No `ref`/`sha` is pinned, so they track the
upstream default branch. Run `/plugin marketplace update` to pull the latest upstream
versions. See [ATTRIBUTIONS.md](ATTRIBUTIONS.md).

## Update

```
/plugin marketplace update
```

Pulls the latest of everything — own plugins from this repo, umputun plugins from upstream.

## Development / CI

The repo ships a small set of check scripts plus a bats test suite. To run them
locally, install the tooling via Homebrew:

```
brew install shellcheck bats-core jq
```

Run the check scripts (each exits non-zero with a clear message on a violation):

```
bash scripts/validate-marketplace.sh
bash scripts/drift-guard.sh
bash scripts/version-sync.sh
bash scripts/link-check.sh
```

Lint every tracked shell script and run the unit tests:

```
shellcheck $(git ls-files '*.sh')
bats tests/
```

Run `shellcheck` from the repo root so it honors the root [`.shellcheckrc`](.shellcheckrc)
(it suppresses the SC2012 `ls`-vs-`find` info finding for a kit detection script).

`.github/workflows/ci.yml` runs all of the above on every push and pull request and
fails the build on any non-zero exit. In CI, `version-sync.sh` runs in diff-aware mode:
it diffs against the base ref and requires any change under `plugins/<own>/**` to bump
that plugin's `plugin.json` version and add a matching `CHANGELOG.md` entry. Run locally
with no base ref, it falls back to static consistency checks.

## License

`autopilot`, `kit`, and `slicer` are MIT (see [LICENSE](LICENSE)). The umputun plugins are
MIT and remain under their original copyright in [umputun/cc-thingz](https://github.com/umputun/cc-thingz).
