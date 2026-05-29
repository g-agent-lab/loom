---
description: Add a new stack overlay to a project that already uses llm-kit
argument-hint: stack name (e.g. python-fastapi, go-stdlib, typescript-nestjs)
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# Kit Overlay

Use this when llm-kit is already installed in the project (via `/kit:init`) and you want to add a new stack overlay — for example, the project initially used `typescript-node-cli` and is now growing a Python service that needs `python-fastapi` rules.

## What you do

1. Verify llm-kit is present:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/ensure-kit.sh check-only
   ```

   If not present, tell the user to run `/kit:init` first and stop.

2. List available overlays:

   ```bash
   ls $(bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/ensure-kit.sh kit-path)/overlays/*.md
   ```

3. If `$ARGUMENTS` is empty, ask the user via AskUserQuestion which overlay to add. Options come from the listing in step 2.

4. Check whether the target overlay is already referenced in the project's `CLAUDE.md`. If yes, report "Overlay `<name>` already referenced — nothing to do." and stop.

5. Add a reference to the overlay in `CLAUDE.md` (under the existing "## Stack" or equivalent section; if no such section, append one).

6. Inspect the overlay file for any stack-specific files it expects (e.g. a `python-fastapi` overlay might mention `pyproject.toml`, `ruff.toml`). Report the inspection summary to the user and ask via AskUserQuestion whether to create them now (delegating to overlay-specific instructions) or just leave the reference and let the user populate manually.

7. Commit:

   ```bash
   git add CLAUDE.md
   git commit -m "chore: add <stack> overlay reference"
   ```

   Skip the commit when `auto_commit_steps` userConfig is false.

Do not modify other files in this command — full overlay scaffolding is the user's responsibility once the reference is in place. The skill's job is only to wire the reference and surface the overlay's expectations.
