---
name: brownfield
description: "Bootstrap llm-kit discipline into an existing legacy project via baseline-and-cleanup-on-touch. Triggers on 'brownfield bootstrap', 'add discipline to legacy project', 'baseline existing project', 'apply universal core to legacy'. Также русские фразы: «дисциплина в legacy», «забутстрапь kit в существующий проект», «baseline существующего проекта», «применить universal core к легаси»."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash:*), AskUserQuestion, TaskCreate, TaskUpdate
---

# brownfield

Walk through llm-kit's `bootstrap/brownfield.md` (13 steps) interactively, applying the LLM-discipline kit to a legacy project that has existing code, commits, and likely existing linter/CI setup. The core difference from greenfield: instead of starting from zero, brownfield **freezes current violations as baselines** and applies discipline via **cleanup-on-touch** going forward.

You are the BOOTSTRAP ORCHESTRATOR. Step content lives in `$KIT_PATH/bootstrap/brownfield.md` and is read live so kit updates propagate. The skill owns workflow: pre-flight → ensure kit → detect stack → 13-step loop (with baselines initialized at current violation counts, not zero) → final verify → wrap-up commit.

## Custom Rules Loading

Same as greenfield. Reads `.claude/kit-rules.md` (project) → `$CLAUDE_PLUGIN_DATA/kit-rules.md` (user) → empty:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh kit-rules.md ${CLAUDE_PLUGIN_DATA}
```

(See greenfield SKILL.md for full rules-management semantics. **CRITICAL: never modify this skill's own files.**)

## Arguments

- `$ARGUMENTS` — optional stack hint. When absent, detected and confirmed with the user.

## Process

### Step 0. Pre-flight

1. Run mode detector:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/detect-mode.sh
   ```

   If output is `greenfield`, report: "This project looks greenfield. Use `/kit:init` to route correctly." Stop.

2. Resolve userConfig (kit_source, kit_install_method, kit_install_path, kit_local_path, auto_install_deps, auto_commit_steps).

3. Detect existing tooling. Inventory using bash:

   ```bash
   ls eslint.config.* .eslintrc* pyproject.toml ruff.toml go.mod package.json 2>/dev/null
   test -f CLAUDE.md && echo "CLAUDE.md exists"
   test -f AGENTS.md && echo "AGENTS.md exists"
   test -d docs/llm-kit && echo "llm-kit already installed at docs/llm-kit"
   test -d external/llm-kit && echo "llm-kit already installed at external/llm-kit"
   ```

   Report the inventory to the user — they should know what's already in place before the skill touches anything.

4. Stack detection (same as greenfield):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/detect-stack.sh
   ```

   If unknown and no `$ARGUMENTS`, ask via AskUserQuestion.

5. Report one-line summary: `Brownfield bootstrap: stack=<STACK>, kit_source=<kit_source>, install=<kit_install_method> at <kit_install_path>`.

### Step 1. Ensure kit is available

```bash
KIT_SOURCE="<kit_source>" KIT_INSTALL_METHOD="<kit_install_method>" \
KIT_INSTALL_PATH="<kit_install_path>" KIT_LOCAL_PATH="<kit_local_path>" \
bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/ensure-kit.sh install
```

Capture `KIT_PATH`. Verify with `verify-step.sh kit-installed`.

### Step 2. Build the task list

Read playbook:

```bash
cat "$KIT_PATH/bootstrap/brownfield.md"
```

Parse `## Шаг N. <title>` headings. For each, create a TaskCreate. Plus meta tasks:

- `TaskCreate(subject="Final verification (baselines frozen)", ...)`
- `TaskCreate(subject="Wrap-up commit", ...)`

### Step 3. Walk through each step

Identical loop to greenfield's Step 3, with these brownfield-specific notes:

1. **Decision steps come up more often.** Brownfield steps frequently ask: "this file already exists — overwrite / merge / skip / append?" Default behaviour: ASK via AskUserQuestion, never auto-overwrite.

2. **Baseline initialization is NOT zero.** Steps that produce `.cross-module-import-baseline.json`, `.dep-cruiser-baseline.json`, `.boundary-baseline.json` capture the CURRENT violations and freeze them as the baseline. New violations beyond baseline fail the gate; existing baselined violations are tolerated until cleanup-on-touch fixes them.

   When a baseline init step runs, report the resulting violation count to the user:

   ```
   Baseline frozen: <baseline-name>
   - violations baselined: <count>
   - gate will fail on any new violation beyond this set
   ```

3. **Existing CLAUDE.md / AGENTS.md handling.** If the user already has these files, the skill MUST NOT silently overwrite. Options to offer via AskUserQuestion:
   - `Merge`: skill emits a diff between current and kit-template, asks user to review and confirm each chunk
   - `Append kit section`: skill appends a "## LLM-Kit Invariants" section to the existing file
   - `Replace`: skill overwrites with the kit template (only when user explicitly chooses)
   - `Skip`: leave the file alone and warn that kit-managed gates may complain later

4. **Pre-existing linter configs handling.** When the kit step wants to set up ESLint / dep-cruiser / similar and a config already exists, ASK before merging. Options:
   - Replace fully with kit's standard config
   - Patch (overlay kit's rules on top of existing)
   - Keep existing and skip (user accepts that kit baselines won't match kit standards)

5. **Verify** each step with `verify-step.sh`. Most verifications pass identical to greenfield. The exception is `baselines-at-zero` — for brownfield, the verify check name is different. We use a relaxed check:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/verify-step.sh baselines-at-zero \
     2>&1 | head -1 || true
   ```

   Brownfield treats `pass` AND `fail: <baseline> not valid JSON` differently. For brownfield, the verify is "baseline files EXIST and are valid JSON" — count can be > 0. If you need a brownfield-specific check, fall back to inline:

   ```bash
   for b in .cross-module-import-baseline.json .dep-cruiser-baseline.json .boundary-baseline.json; do
       [ -f "$b" ] && python3 -c "import json; data = json.load(open('$b')); print('baseline:', '$b', 'violations:', len(data) if isinstance(data, list) else sum(len(v) if isinstance(v, list) else 1 for v in data.values()))"
   done
   ```

6. **Commit per step** if `auto_commit_steps` is true. Otherwise accumulate for final commit.

CRITICAL: brownfield does NOT promise zero violations — it promises baselines at current state and gates that catch new violations. Communicate that to the user clearly in the final summary.

CRITICAL: never delete or rename pre-existing user files. Brownfield is additive (new files + new configs) plus baseline-based gating; existing code stays untouched until cleanup-on-touch policy triggers per-touch fixes.

### Step 13/N. Final verification (baselines frozen)

```bash
LINT_COMMAND="<stack-specific lint command>" \
bash ${CLAUDE_PLUGIN_ROOT}/skills/greenfield/scripts/verify-step.sh lint-passes
```

For brownfield, the lint command should pass (because baselines tolerate existing violations). If it fails, the baseline didn't capture all current violations — report the gap and ask the user whether to regenerate baselines or fix the residue.

Report the final state including baseline violation counts:

```
Brownfield bootstrap done. <STACK> stack.
Baselines frozen:
  cross-module-imports: N violations baselined
  dep-cruiser: M violations baselined
  boundary: K violations baselined
Cleanup-on-touch policy: any touched file's violations must be fixed before the touch's commit. New violations beyond baseline → gate fails.
```

### Step 14. Wrap-up commit

```bash
git add -A
git status
git commit -m "chore: bootstrap llm-kit v<version> on legacy <STACK> project (baselines frozen)"
```

(Skip if `auto_commit_steps` was true.)

Report final `git log --oneline -5` and:

```
Wrap-up done. Suggest: read docs/DOCS_RULES.md, browse the baseline files,
review the "Cleanup-on-touch" section in $KIT_PATH/UNIVERSAL_CORE.md.
```

## Key differences vs greenfield

| Aspect | Greenfield | Brownfield |
|---|---|---|
| Initial commit | empty / fresh | existing history preserved |
| CLAUDE.md / AGENTS.md | always created from template | merge / append / replace decision per file |
| Baseline files | initialised at 0 | initialised at current violation count |
| Lint at end | must pass clean | must pass within baselined tolerances |
| Decision steps | rare (stack, branch name) | frequent (overwrite vs merge vs skip per file) |
| Final state | clean discipline from day 1 | discipline applied via cleanup-on-touch policy going forward |

## Key Rules

(Same as greenfield, plus:)

- The skill captures current violations as baselines — it does NOT auto-fix existing code.
- "Cleanup-on-touch" means: every commit that modifies a baselined file MUST fix that file's baselined violations within that commit. Communicate this expectation to the user at the end.
- Pre-existing user content (configs, docs) is preserved by default. Only explicit user consent overwrites.
- The skill never pushes.
