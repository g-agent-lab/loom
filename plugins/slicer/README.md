# slicer

Turns a **ready draft** into **ralphex-executable iteration plans**, strictly and
verifiably. This is the missing link between drafting (`brainstorm` / `planning:make`)
and execution (`autopilot` / `planning:exec`): it takes a draft you've already vetted
and slices it into one or more plan packs that the [ralphex](https://github.com/umputun/ralphex)
engine can run without surprises.

## What it does

The `slice-draft-to-plans` skill walks a 9-step pipeline:

1. **Pre-slicing gate** — refuses to slice until the draft is ready (Codex blockers
   closed, explicit scope + acceptance criteria, API surface verified against real code,
   user authorized).
2. **Pack split** — decides 1 vs N packs by task count (≤7 → one, 8-14 → two, 15+ → three).
3. **Template** — fills the bundled `ralphex-plan-template.md` skeleton.
4. **Parser-strict tasks** — emits `### Task N:` / `### Iteration N:` + `- [ ]` checkboxes.
5. **Sizing** — 3-7 tasks/plan, 30-150 LOC/task, linear deps, mandatory tests.
6. **Required final tasks** — `Verify acceptance criteria` + `Update documentation`.
7. **Naming** — `docs/plans/active/<pack-id>-<slug>.md`.
8. **ROADMAP** — links the new pack.
9. **Self-verify** — checks parser tokens, sizing, file existence.

## Why "verifiable"

The parser contract in this skill is **verified against the real ralphex engine**
(`umputun/ralphex`, `pkg/plan/parse.go`), not assumed. Notably:

- The engine accepts **both** `### Task N:` and `### Iteration N:`.
- The task number is parsed with `strconv.Atoi` — non-integers don't break parsing
  (they become task `0`), so "number from 1" is an ordering convention, not a hard rule.
- The task **title language is irrelevant to the parser**; only the literal keyword
  `Task`/`Iteration` and the colon matter. Translating the keyword (`### Шаг N:`) is what
  breaks detection.
- Checkbox lines may be **indented**; `##` (h2) closes a task while `###`/`####` do not;
  a checkbox whose text contains `[ ]`/`[x]` is treated as a format example and ignored.

## Usage

Trigger in natural language — English ("slice this draft", "create iteration plan",
"prepare ralphex") or Russian («нарезать draft», «сделать ralphex план»). The skill
loads automatically when the request matches.

## Relationship to llm-kit

This skill originated in [llm-kit](https://github.com/g-agent-lab/llm-kit) and was
promoted to a standalone marketplace plugin so it can be installed once globally rather
than copied per-project at bootstrap. It is the single source of truth; llm-kit no longer
ships a copy.
