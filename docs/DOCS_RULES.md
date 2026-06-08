# Documentation rules — loom marketplace

> Source of truth for the structure and freshness of `docs/`. When in doubt,
> check against the rules below. Canon above this file:
> [llm-kit](https://github.com/g-agent-lab/llm-kit) `UNIVERSAL_CORE.md` §5.
>
> This repo applies the **universal** documentation discipline only; it is a
> Markdown/shell/JSON marketplace, not a TypeScript app, so the stack-specific
> reference docs (`data-model.md`, `api-endpoints.md`) and `modules/` are not
> used. See [`reference/architecture-exemptions.md`](reference/architecture-exemptions.md).

## `plans/` structure

```
plans/
  ROADMAP.md              ← compact overview (where we are / what's next)
  drafts/                 ← design drafts for discussion (sortable NN- prefix)
    done/                 ← drafts whose plans are all completed (manual move)
  active/                 ← runnable plans (executed by the autopilot plugin)
    completed/            ← completed plans (autopilot mark-completed / manual move)
```

### Plan lifecycle (as practiced here)

```
1. Idea          → a line in ROADMAP.md "Что дальше / Next"
2. Draft         → plans/drafts/NN-feature.md (discuss with the LLM; NN = priority)
3. Slice         → plans/active/<slug>.md  (via the `slicer` plugin; header links the draft)
4. Execute       → the `autopilot` plugin runs the queue via /planning:exec
5. Complete      → finished plans move to plans/active/completed/ (autopilot / manual)
6. ROADMAP       → move the line from "Next" to "Done"
```

`plans/active/completed/` is the ralphex-native completed location — the same path
the `autopilot` plugin's `mark-completed.sh` writes to when the queue runs on
`plans/active/`.

### Rules

- No `.md` files in `plans/` root except `ROADMAP.md`.
- Each plan in `active/` has a header link to its draft.
- `drafts/done/` holds only drafts whose plans are all completed.
- Live drafts use a sortable `NN-` prefix matching their order in `ROADMAP.md`.

## Entry points

| File | Rules |
|------|-------|
| [`../README.md`](../README.md) | Stack, plugin count, test counts, tree — must match reality |
| [`CONTEXT.md`](CONTEXT.md) | LLM entry point. No long "✅ done" tables. Links into `plans/`. Notes what not to read by default |
| [`SESSION.md`](SESSION.md) | Only the current session's entries. >100 lines → rotate to `changelog/YYYY-MM.md` |
| [`../AGENTS.md`](../AGENTS.md) | Pointer to `CLAUDE.md` (exemption #3: pointer form, not an operational subset, so the two can never drift) |

## Reference docs

| File | What docs-lint / review checks |
|------|--------------------------------|
| [`reference/env-variables.md`](reference/env-variables.md) | Every env var **read but never assigned** in `*.sh` is listed (enforced by `scripts/docs-lint.sh`) |
| [`reference/contracts.md`](reference/contracts.md) | Manifest / `plugin.json` / MCP / config-file contracts stay accurate |
| [`reference/module-routing.md`](reference/module-routing.md) | Zones and "where to put new logic" reflect the real tree |
| [`reference/architecture-exemptions.md`](reference/architecture-exemptions.md) | Every deviation from llm-kit universal core is listed with a reason |

The `ralphex-plan-template.md` reference lives in the `slicer` plugin
(`plugins/slicer/skills/slice-draft-to-plans/ralphex-plan-template.md`) — slicer
is its single source of truth; it is **not** duplicated under `docs/reference/`.

## `ROADMAP.md`

- "В работе / In progress" = each item has a file in `plans/active/`.
- "Что дальше / Next" = each item with a draft has a file in `plans/drafts/`.
- No in-progress item without a file in `active/`; no completed item still listed
  as in progress.

## `SESSION.md` — entry format

```markdown
### [YYYY-MM-DD] <Title>
- Files: `path/a`, `path/b`, ...
- Change: (1) ...; (2) ...; (3) ...
- Reason: <why — brief>
```

If a day has several edits, keep ONE entry merging the changes into a numbered list.

### SESSION.md → changelog rotation

When `wc -l docs/SESSION.md` exceeds 100:

1. Open `docs/changelog/YYYY-MM.md` (current month; create if missing).
2. Cut the **old** entries out of SESSION.md (everything but the current session).
3. Paste them at the top of the changelog (sorted by date, descending).
4. Leave a marker at the bottom of SESSION.md: `_(Entries … and earlier rotated to changelog/YYYY-MM.md)_`.
5. Lose nothing — the diff should show only a move.

> `docs/changelog/` is the rotated **session journal**. It is distinct from the
> root [`../CHANGELOG.md`](../CHANGELOG.md), which is the **own-plugin** changelog
> (`autopilot`/`kit`/`slicer`) enforced by `scripts/version-sync.sh`.

## docs-lint

`scripts/docs-lint.sh` (bash + `jq`/`grep`/`awk`, like the other checks) enforces
the machine-checkable subset of these rules:

1. The universal docs exist (`CONTEXT.md`, `DOCS_RULES.md`, `SESSION.md`, `plans/ROADMAP.md`).
2. Every env var read-but-not-assigned in `*.sh` appears in `reference/env-variables.md`.
3. Every plan in `plans/active/` (not `completed/`) references a draft.
4. `SESSION.md` ≤ 100 lines (warning, not a failure).

It runs in CI alongside the other check scripts and is covered by `tests/docs-lint.bats`.

## Session audit prompt

Paste at the start of a session to audit the docs:

```
Read docs/DOCS_RULES.md and run a full check:
1. plans/ structure
2. Entry points
3. Reference docs
4. ROADMAP.md
List violations. If none — write "Docs OK".
```
