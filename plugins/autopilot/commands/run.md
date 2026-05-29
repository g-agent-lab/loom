---
description: Run a queue of plan files sequentially via /planning:exec
argument-hint: optional plans directory (default plans_dir userConfig, e.g. docs/plans/active)
allowed-tools: Skill
---

# Autopilot Run

Invoke the `batch` skill to discover plans in the given directory (or `plans_dir` userConfig default) and execute them sequentially via `/planning:exec`.

Use the Skill tool to invoke `autopilot:batch` with `$ARGUMENTS` as the directory path. Pass an empty string when no argument was given — the skill falls back to the `plans_dir` userConfig default.
