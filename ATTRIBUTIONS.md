# Attributions

This marketplace re-exposes seven plugins from
[umputun/cc-thingz](https://github.com/umputun/cc-thingz) (MIT License,
copyright © Umputun).

**They are referenced, not copied.** Each is declared in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) with a
`git-subdir` source pointing directly at the upstream repository:

- brainstorm
- planning
- review
- release-tools
- thinking-tools
- skill-eval
- workflow

No upstream source files are vendored into this repository. No `ref`/`sha` is
pinned, so these plugins track the upstream default branch and update via
`/plugin marketplace update`.

Upstream reference point at the time this marketplace was created:
`e2478e204403953707e307bf490a1e54e99adbce` (2026-05-18). This is informational
only — the marketplace is not pinned to it.

The `autopilot` and `kit` plugins are original work © 2026 g-agent-lab, MIT
licensed (see [LICENSE](LICENSE)). `autopilot` is designed to drive cc-thingz's
`planning` plugin; `kit` bootstraps [g-agent-lab/llm-kit](https://github.com/g-agent-lab/llm-kit).
