# kit

Interactive Claude Code plugin that bootstraps the [llm-kit](https://github.com/g-agent-lab/llm-kit) LLM-discipline kit into any project — greenfield or brownfield — through opinionated skills in the same style as [umputun/cc-thingz](https://github.com/umputun/cc-thingz).

```
mkdir my-new-project && cd my-new-project
claude
> /kit:init
```

kit detects greenfield vs brownfield, asks for the stack, ensures `external/llm-kit/` is present, then walks through llm-kit's bootstrap playbook (13 steps) interactively. Each step is announced, executed, verified, and either committed or accumulated for a single final commit.

## Why

llm-kit is a portable markdown kit. Applying it to a project today means: `git submodule add llm-kit`, open `bootstrap/greenfield.md`, run 13 steps by hand, remember the verify check at each step, configure ralphex global + per-project, copy 6 universal scripts, copy 3 hooks, initialise 3 baseline files, run lint to confirm zero violations. Takes 30-45 minutes if you remember everything.

kit reduces that to a single `/kit:init` invocation. The plugin reads the playbook live (so kit updates propagate without plugin upgrade), runs each step, verifies each step, and asks the user only at genuine decision points.

You can also trigger it in natural language — English ("bootstrap llm-kit", "set up new project") or Russian («забутстрапь kit», «поставь дисциплину в новый проект»).

## Commands

| Command | Use when |
|---|---|
| `/kit:init` | Bootstrap a project. Auto-routes to greenfield or brownfield skill. |
| `/kit:overlay <stack>` | Add a new stack overlay to an existing kit-using project. |

## Skills (invocable directly)

| Skill | Purpose |
|---|---|
| `kit:greenfield` | Bootstrap from a fresh, empty project. |
| `kit:brownfield` | Bootstrap on a legacy project; freezes current violations as baselines. |

## userConfig

| Key | Default | Purpose |
|---|---|---|
| `kit_source` | `https://github.com/g-agent-lab/llm-kit.git` | Kit repo URL |
| `kit_install_method` | `submodule` | `submodule` \| `copy` \| `local` |
| `kit_install_path` | `external/llm-kit` | Where kit lives inside the project |
| `kit_local_path` | _(empty)_ | Local kit checkout (when install_method=local) |
| `default_branch` | `main` | Initial branch for greenfield |
| `auto_install_deps` | `true` | Auto-run package install commands |
| `auto_commit_steps` | `false` | One commit per step vs one final commit |

## Architecture

kit is the **driver** (Claude Code plugin, ~600 lines markdown + shell). llm-kit is the **content source of truth** (markdown playbook + templates).

- Playbook (`bootstrap/greenfield.md`, `bootstrap/brownfield.md`) is parsed live.
- Templates (`bootstrap/templates/*`) are copied verbatim into the project.
- Overlays (`overlays/<stack>.md`) provide stack-specific commands and configs.
- Updates to llm-kit propagate to kit users via `git submodule update` — no plugin upgrade required.

## Install

Part of the [`g-agent-lab/loom`](https://github.com/g-agent-lab/loom) marketplace:

```
/plugin marketplace add g-agent-lab/loom
/plugin install kit@loom
```

Restart Claude Code to pick up the new commands and skills.

## Custom rules

Project: `.claude/kit-rules.md`
User: `$CLAUDE_PLUGIN_DATA/kit-rules.md`

See `references/custom-rules.md` for the full rules mechanism.

## Known limitations

- Playbook parsing assumes Russian step headings (`## Шаг N. <title>`).
- Only `submodule` install method end-to-end smoke-tested.
- Single-stack bootstrap; additional stacks added via `/kit:overlay`.
- No rollback — bootstrap failures require manual `git reset --hard`.

## License

MIT.
