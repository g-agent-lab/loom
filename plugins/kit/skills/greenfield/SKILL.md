---
name: greenfield
description: "Bootstrap llm-kit discipline into a brand-new project. Triggers on 'bootstrap llm-kit', 'init project with discipline', 'set up new project', 'apply universal core', 'green-field bootstrap'. Также русские фразы: «забутстрапь kit», «поставь дисциплину в новый проект», «бутстрап нового проекта», «применить universal core»."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash:*), AskUserQuestion, TaskCreate, TaskUpdate
---

# greenfield

Walk through llm-kit's `bootstrap/greenfield.md` (13 steps) interactively, applying the LLM-discipline kit to a brand-new project that has no commits, no linter configs, and no `CLAUDE.md`.

You are the BOOTSTRAP ORCHESTRATOR. You do NOT invent rules. Step content (commands, configs, templates) is read live from `<kit-path>/bootstrap/greenfield.md` so updates to the kit propagate without skill changes. Your job is the WORKFLOW: pre-flight → ensure kit → detect stack → 13-step loop → final verify → first commit.

## Custom Rules Loading

Before starting, run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh kit-rules.md ${CLAUDE_PLUGIN_DATA}
```

If non-empty, treat as additional instructions throughout the bootstrap. See `${CLAUDE_PLUGIN_ROOT}/references/custom-rules.md`.

### Rules Management

- **show**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh kit-rules.md ${CLAUDE_PLUGIN_DATA}`.
- **add/update project**: write `.claude/kit-rules.md`.
- **add/update user**: write `$CLAUDE_PLUGIN_DATA/kit-rules.md` (only when set).
- **clear**: delete the file.

**CRITICAL: never modify this skill's own files.** Only `.claude/kit-rules.md` and `$CLAUDE_PLUGIN_DATA/kit-rules.md` are writable for rules management.

## Arguments

- `$ARGUMENTS` — optional stack hint that maps to an llm-kit overlay (e.g. `typescript-node-cli`, `typescript-nestjs`, `python-fastapi`, `go-stdlib`). When absent, stack is detected from filesystem signals and confirmed with the user.

## Process

### Step 0. Pre-flight

1. Run the mode detector to confirm we're in greenfield territory:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/detect-mode.sh
   ```

   If the output is `brownfield`, report to the user: "This project looks brownfield (has commits / linter configs / CLAUDE.md). Use `/kit:init` to route to the brownfield skill, or pass `--force-greenfield` if you really want the greenfield path." Stop.

2. Read userConfig (resolved by the runtime from `plugin.json`): `kit_source`, `kit_install_method`, `kit_install_path`, `kit_local_path`, `default_branch`, `auto_install_deps`, `auto_commit_steps`. Use these as env vars when invoking scripts.

3. Stack detection:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/detect-stack.sh
   ```

   If `$ARGUMENTS` is set, prefer it over auto-detect. If detect script returns `unknown` AND no `$ARGUMENTS`, ask the user via AskUserQuestion to pick from:
   - typescript-node-cli
   - typescript-nestjs
   - python-fastapi
   - python-aiogram
   - go-stdlib

   Store the chosen stack as `STACK`.

4. Report a one-line summary: `Greenfield bootstrap: stack=<STACK>, kit_source=<kit_source>, install=<kit_install_method> at <kit_install_path>`.

### Step 1. Ensure kit is available

```bash
KIT_SOURCE="<kit_source>" KIT_INSTALL_METHOD="<kit_install_method>" \
KIT_INSTALL_PATH="<kit_install_path>" KIT_LOCAL_PATH="<kit_local_path>" \
bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/ensure-kit.sh install
```

The script idempotently installs the kit (submodule / copy / local). Capture the kit path (printed on stdout, first line) as `KIT_PATH`.

Verify: `bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/verify-step.sh kit-installed`.

### Step 2. Build the task list

Read the bootstrap playbook from disk so the task list reflects what's actually in the kit (kit may have evolved):

```bash
cat "$KIT_PATH/bootstrap/greenfield.md"
```

Parse the playbook's step headings (`## Шаг N. <title>`). For each, create a TaskCreate item:

- `TaskCreate(subject="Step N: <title>", description="<first 80 chars of step's intro>", activeForm="Running Step N...")`

Plus three meta tasks:

- `TaskCreate(subject="Final verification", description="run lint, baselines, dep-cruiser", activeForm="Verifying...")`
- `TaskCreate(subject="First commit", description="commit bootstrap artifacts", activeForm="Committing...")`

Store the taskIds in step order.

### Step 3. Walk through each step

For each playbook step in order (from Step 1 to the last numbered step):

1. **Announce** to the user with a banner that includes the step number, title, and a short user-facing summary derived from the step's intro:

   ```
   --- Step N: <title> ---
   <one-sentence summary>
   ```

2. `TaskUpdate(stepTaskId, status="in_progress")`.

3. **Decide step kind** by inspecting the step's content. Three kinds:

   - **Automated step** — pure shell commands with no decision points. Examples: file creates, git commands, copy templates, install deps. Execute the commands as documented in the playbook step. When the step references templates under `bootstrap/templates/`, copy them into the project at the documented destination using `cp`.
   - **Decision step** — requires user input (e.g. project name, branch name, executor choice). Use AskUserQuestion to gather the decision, then apply.
   - **Stack-specific step** — content depends on the chosen stack overlay. Read the relevant section from `$KIT_PATH/overlays/<STACK>.md` and execute the documented commands for that stack.

4. **Apply the step**.

   When copying scripts/hooks from kit templates, preserve executable bits:

   ```bash
   cp "$KIT_PATH/bootstrap/templates/scripts/<name>.cjs" scripts/
   cp "$KIT_PATH/bootstrap/templates/hooks/<name>.sh" .claude/hooks/
   chmod +x .claude/hooks/*.sh
   ```

   When creating CLAUDE.md or AGENTS.md from templates, replace `<PROJECT_NAME>` and other placeholders with concrete values before writing.

5. **Verify** the step using the appropriate verify-step.sh check (see verify-step.sh source for the list of supported step names). Map step number/title to a verify name:
   - Step 1 → `git-init`
   - Step 2 → `ralphex-installed`
   - Step 5 → `kit-installed` (already done in Step 1 here; re-verify is fine)
   - Step 6 → `claude-md-present`
   - Step 7 → `agents-md-present`
   - Step 8 → `gitignore-has-essentials`
   - Step 9 → `universal-scripts-present`
   - Step 10 → `hooks-installed`
   - Step 11 → `docs-rules-present`
   - Step 12 → `baselines-at-zero`

   Run the matching verify. If `pass` → continue. If `fail: <reason>` → report failure to user and ask whether to retry, edit-and-retry, or abort.

6. **Commit per step** if `auto_commit_steps` userConfig is true:

   ```bash
   git add -A && git commit -m "chore: kit Step N — <title>"
   ```

   Otherwise accumulate changes for a single final commit (Step 14).

7. `TaskUpdate(stepTaskId, status="completed")`.

CRITICAL: never improvise content. If a step's commands or templates are missing from `$KIT_PATH`, stop and report "kit playbook references missing artifact: <path>" — do not invent substitutes.

CRITICAL: never run `git push`. Bootstrap stays local; the user pushes manually when they want to.

CRITICAL: never delete pre-existing user files. If a step expects to create a file that already exists with non-trivial content (e.g. user-edited `README.md`), pause and ask the user whether to overwrite, merge, or skip.

### Step 13/N. Final verification

After all numbered steps:

```bash
LINT_COMMAND="<stack-specific lint command>" \
bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/verify-step.sh lint-passes
```

The stack-specific lint command comes from the chosen overlay (e.g. `npm run lint` for typescript-node-cli). Report:

- All N steps applied
- All verifications pass
- Baselines at zero (from `baselines-at-zero` verify already)
- Final lint check: pass/fail

If anything fails, report concretely and ask whether to retry or hand off to the user.

### Step 14. First commit

```bash
git add -A
git status
git commit -m "chore: bootstrap llm-kit v<kit-version> for <STACK> stack"
```

(Skip when `auto_commit_steps` is true — per-step commits already exist.)

Report the resulting `git log --oneline -5` and a final line:

```
Bootstrap done. <STACK> stack, llm-kit v<version> installed at <KIT_PATH>.
Suggest: review CLAUDE.md, AGENTS.md, docs/DOCS_RULES.md, then push when ready.
```

`TaskUpdate(finalCommitTaskId, status="completed")`.

## Key Rules

- Playbook content (commands, templates, configs) lives in `$KIT_PATH`. The skill walks the playbook; it doesn't replace it.
- One playbook = many step kinds. Read each step's intent before executing.
- Stack overlays carry stack-specific files (`.gitignore` template, lint command, dep-cruiser config). Always consult `$KIT_PATH/overlays/<STACK>.md` for stack-specific bits.
- The skill commits only if `auto_commit_steps=true`. Otherwise one final commit at Step 14.
- Verifications use `verify-step.sh` — each step that produces a checkable artifact has a verify recipe. If a verify fails, the skill pauses and asks.
- The skill never pushes, never deletes user files, never invents missing kit content.
- Custom rules from `.claude/kit-rules.md` supplement the playbook but cannot bypass core invariants (kit playbook ordering, mandatory gates).
