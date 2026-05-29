# cc-kit Usage

Bootstrap the [llm-kit](https://github.com/g-agent-lab/llm-kit) discipline kit into any project — new or legacy — through interactive Claude Code skills, in the same style as [umputun/cc-thingz](https://github.com/umputun/cc-thingz).

## Commands

| Command | Use when |
|---|---|
| `/kit:init` | Bootstrap a project. Auto-detects greenfield vs brownfield, routes to the matching skill. |
| `/kit:overlay <stack>` | Add a new stack overlay to a project that already has llm-kit installed. |

## Skills

| Skill | Triggered by `/kit:init` when |
|---|---|
| `kit:greenfield` | Project has no git history, no linter configs, no `CLAUDE.md` |
| `kit:brownfield` | Anything else (legacy / partially-set-up project) |

You can also invoke a skill directly: `/kit:greenfield typescript-node-cli` or `/kit:brownfield`.

## Workflow

### Greenfield (new project)

```
mkdir my-new-project && cd my-new-project
claude
> /kit:init
```

The skill:

1. Confirms greenfield via pre-flight (no `.git`, no linter configs, no `CLAUDE.md`).
2. Asks for stack (or autodetects when `package.json` / `pyproject.toml` / `go.mod` is already present).
3. Ensures `external/llm-kit/` exists (clones via submodule by default).
4. Reads `external/llm-kit/bootstrap/greenfield.md` and walks through its 13 steps:
   - `git init`, `.gitignore`, README placeholder
   - Install ralphex (skipped if already present)
   - Configure ralphex global + per-project
   - Apply CLAUDE.md, AGENTS.md, docs/DOCS_RULES.md from kit templates
   - Copy universal scripts (`scripts/*.cjs`) and hooks (`.claude/hooks/*.sh`)
   - Initialise baselines at zero
   - Verify lint clean
5. Commits the bootstrap (single commit by default; per-step commits when `auto_commit_steps=true`).

### Brownfield (legacy project)

```
cd my-existing-project
claude
> /kit:init
```

Same flow, but the brownfield skill:

- Detects pre-existing tooling and reports an inventory before touching anything.
- Asks per-file what to do (overwrite / merge / append / skip) when CLAUDE.md / AGENTS.md / linter configs already exist.
- Initialises baselines at **current** violation counts (not zero) and freezes them. Going forward, gates fail on NEW violations beyond baseline; existing violations are tolerated until cleanup-on-touch fixes them.
- Wraps up with a single commit including baselines and any new templates.

### Adding a stack overlay later

If you bootstrapped with `typescript-node-cli` and a new service in Python joins later:

```
> /kit:overlay python-fastapi
```

The skill adds a reference to `overlays/python-fastapi.md` in your `CLAUDE.md` and surfaces the overlay's requirements (e.g. `pyproject.toml`, `ruff.toml`) without auto-creating them — you decide what to populate.

## userConfig

| Key | Default | Purpose |
|---|---|---|
| `kit_source` | `https://github.com/g-agent-lab/llm-kit.git` | URL to clone kit from when missing |
| `kit_install_method` | `submodule` | `submodule` \| `copy` \| `local` |
| `kit_install_path` | `external/llm-kit` | Where the kit lives inside the project |
| `kit_local_path` | _(empty)_ | When `install_method=local`, path to an existing local checkout |
| `default_branch` | `main` | Initial branch for greenfield Step 1 |
| `auto_install_deps` | `true` | Auto-run `npm install` / `pip install` / `go mod tidy` when overlays specify it |
| `auto_commit_steps` | `false` | When true, one commit per bootstrap step; when false, one final commit |

## Custom rules

Project: `.claude/kit-rules.md`
User: `$CLAUDE_PLUGIN_DATA/kit-rules.md`

Project takes precedence. Rules supplement (not replace) the kit playbook. They can influence:

- Stack detection priority (e.g. "prefer python-aiogram over python-fastapi when both signals are present").
- Default branch name override.
- Auto-commit policy per project.
- Reporting verbosity.
- File-handling defaults during brownfield (e.g. "always append, never overwrite" for CLAUDE.md).

Rules cannot bypass kit playbook ordering or skip mandatory gates.

## Relationship to llm-kit

cc-kit is the **driver**. llm-kit is the **content source of truth**.

- llm-kit lives at https://github.com/g-agent-lab/llm-kit, currently v1.3.
- cc-kit reads the playbook (`bootstrap/greenfield.md`, `bootstrap/brownfield.md`), overlays (`overlays/<stack>.md`), and templates (`bootstrap/templates/*`) live from the installed kit at runtime.
- Updates to llm-kit (new overlays, refined templates, additional steps) propagate to cc-kit users **automatically** via `git submodule update` (or by re-cloning when using `copy` method) — no cc-kit upgrade required.

When llm-kit's bootstrap step ordering or step contract changes structurally (rare), cc-kit's skill orchestration may need a bump. Step content changes (commands, templates, configs) flow through transparently.

## Known limitations (v0.1)

- Step parsing assumes the playbook uses Russian headings (`## Шаг N. <title>`). The skill matches this exact pattern via `grep -E '^## Шаг [0-9]+\.'`. If llm-kit adds English-language playbook variants, the skill needs a parser update.
- Only `submodule` install method has been smoke-tested. `copy` and `local` are implemented but unverified end-to-end.
- Single-stack per bootstrap. Multi-stack projects (e.g. Python + Go in one repo) need `/kit:overlay` invoked once per additional stack after `/kit:init`.
- No rollback. If bootstrap fails mid-flight, the user manually `git reset --hard` or rolls back per their preferred workflow.
- `verify-step.sh` covers 11 step names today. Steps without a verify recipe rely on user inspection.
