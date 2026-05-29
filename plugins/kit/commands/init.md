---
description: Bootstrap llm-kit discipline into this project (auto-detects greenfield vs brownfield)
argument-hint: optional stack hint (e.g. typescript-node-cli, typescript-nestjs)
allowed-tools: Bash, Skill
---

# Kit Init

Entry point for the kit bootstrap workflow.

## What you do

1. Detect whether this project is **greenfield** or **brownfield** using a fast bash check. Greenfield = no git history AND no linter configs AND no `CLAUDE.md`. Anything else is brownfield.

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/detect-mode.sh
   ```

   The script prints `greenfield` or `brownfield` on stdout.

2. Report the detected mode to the user with one line: `Detected: <mode>`.

3. Invoke the matching skill via the **Skill** tool:
   - `greenfield` → invoke `kit:greenfield` with `$ARGUMENTS` (optional stack hint)
   - `brownfield` → invoke `kit:brownfield` with `$ARGUMENTS`

4. Do not perform bootstrap work yourself in this command — the skill owns the orchestration. Your only job here is detection + routing.
