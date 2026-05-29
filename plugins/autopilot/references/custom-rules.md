# Custom Queue Rules

The queue skill supports user-provided custom rules loaded at the start of each run. Rules are additional instructions that supplement (not replace) the built-in process. They are applied throughout the queue: during discovery filtering, worktree decisions, per-plan reporting, and failure handling.

## Resolution Chain

```
1. .claude/queue-rules.md        (project — repo-local override)
2. $CLAUDE_PLUGIN_DATA/queue-rules.md   (user — applied across all projects)
3. (empty / no rules)
```

**First non-empty file wins.** Levels are NOT merged. An empty file at a higher level falls through to the next level (treated as absent).

This mirrors the planning plugin's `resolve-rules.sh` semantics so the two plugins stay consistent.

## File Format

Plain markdown. No frontmatter required. Rules are read by the LLM and applied as guidance — there is no machine parser, no schema validation.

Example:

```markdown
# Queue rules for this project

- Skip plans whose filename starts with `draft-` or `wip-`.
- When `stop_on_failure` would trigger, instead append a one-line note to
  `docs/plans/active/INBOX.md` before stopping, so a future queue run sees
  the failure context.
- After every 3 successful plans, run `git status` and report whether the
  working tree is clean (helpful for catching cross-plan leaks in
  `shared` worktree mode).
- Always prefer `per_plan` worktree even if userConfig says `shared`.
```

## Limits

Rules MUST NOT override:

- The `### Task N:`/`### Iteration N:` heading recognition (plan format).
- The `[x]` checkbox completion criterion.
- The Skill tool invocation pattern for `/planning:exec`.
- File-modification restrictions (queue may only `mv` plans, never edit them).

Rules MAY influence:

- Discovery filtering (exclude or reorder plans).
- Reporting verbosity and format.
- Pre/post-plan actions (e.g. write to an inbox, run a status check).
- Failure routing (stop / continue / append-note / pause).

## Managing Rules

The queue skill responds to "show / add / clear queue rules" requests by writing or deleting the appropriate file via Bash, never by editing its own SKILL.md. See the **Rules Management** section in `SKILL.md` for the exact commands.

## Comparison to planning's rules

Both plugins use the same `resolve-rules.sh` script semantics, but they read DIFFERENT files:

- planning → `planning-rules.md`
- queue → `queue-rules.md`

Rules for one plugin do not affect the other. If you want the same rule to apply to both, write it into both files (no symlink mechanism is provided — keeping the namespaces independent simplifies override resolution).
