# loom

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace.

Two plugins of my own — `autopilot` and `kit` — plus the seven plugins from
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
/plugin install planning@loom
```

## Plugins

| Plugin | What it does | Origin |
|---|---|---|
| `autopilot` | Run a queue of plan files sequentially and autonomously via `/planning:exec`, each in its own git worktree | own |
| `kit` | Bootstrap [llm-kit](https://github.com/g-agent-lab/llm-kit) discipline (greenfield + brownfield) into any project | own |
| `brainstorm` | Collaborative design dialogue — idea → approaches → design → plan | umputun/cc-thingz |
| `planning` | Structured implementation planning + autonomous plan execution | umputun/cc-thingz |
| `review` | PR review, git diff annotation review, writing style guide | umputun/cc-thingz |
| `release-tools` | Release workflow — versioning, release notes, changelog | umputun/cc-thingz |
| `thinking-tools` | Dialectic, root-cause investigator, ask-codex | umputun/cc-thingz |
| `skill-eval` | Forces skill evaluation before every response | umputun/cc-thingz |
| `workflow` | Session helpers — learn, clarify, wrong, clipboard copy | umputun/cc-thingz |

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

## License

`autopilot` and `kit` are MIT (see [LICENSE](LICENSE)). The umputun plugins are MIT and
remain under their original copyright in [umputun/cc-thingz](https://github.com/umputun/cc-thingz).
