# Custom kit rules

The cc-kit skills (`kit:greenfield`, `kit:brownfield`, `kit:overlay`) support user-provided custom rules loaded at the start of each invocation. Rules are additional instructions applied throughout the bootstrap.

## Resolution chain

```
1. .claude/kit-rules.md                  (project — repo-local)
2. $CLAUDE_PLUGIN_DATA/kit-rules.md      (user — applies across all projects)
3. (empty)
```

**First non-empty wins.** No merging. An empty file at a higher level falls through to the next.

## File format

Plain markdown. No schema. The LLM reads rules as guidance.

## Example rules

```markdown
# Kit rules for this user

## stack detection
- For unknown stack signals, prefer `typescript-node-cli` over `typescript-nestjs`.

## brownfield decisions
- For pre-existing CLAUDE.md, always default to "Append kit section" (no need to ask each time).
- For pre-existing eslint configs, always default to "Patch (overlay kit rules)".

## commit policy
- Override `auto_commit_steps` to true even when the userConfig default is false.
- All bootstrap commits use the prefix `chore(bootstrap):` instead of `chore:`.

## reporting
- After each step, print a one-line cost estimate to stdout (assuming token rates from CLAUDE.md).
```

## What rules cannot do

Rules MUST NOT override:

- The 13-step ordering defined by llm-kit's playbook.
- Mandatory gates (lint, baselines, dep-cruiser config).
- File overwrite safety (skill must still ask before overwriting non-trivial user files).
- `git push` prohibition (skill never pushes).

Rules MAY influence:

- Default answers to AskUserQuestion prompts (skill can pre-select an option based on rules).
- File-handling defaults during brownfield (overwrite / merge / append / skip).
- Reporting style and verbosity.
- Stack detection priority on ambiguous inputs.
- Auto-commit and auto-install-deps defaults.

## Managing rules

The skills respond to "show / add / clear kit rules" requests by writing or deleting `.claude/kit-rules.md` (or `$CLAUDE_PLUGIN_DATA/kit-rules.md` for user-level). They never modify the SKILL.md files themselves. See the "Rules Management" section in each SKILL.md.
