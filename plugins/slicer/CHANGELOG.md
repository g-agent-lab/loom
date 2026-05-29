# Changelog

## 0.1.0

Initial release. Promotes `slice-draft-to-plans` from an llm-kit bootstrap template to a
standalone marketplace plugin (single source of truth).

- `slice-draft-to-plans` skill: 9-step draft → ralphex iteration plan pipeline
  (pre-slicing gate, pack split, parser-strict tasks, sizing, required final tasks,
  naming, ROADMAP, self-verify).
- Bundled `ralphex-plan-template.md` skeleton.
- **Parser contract verified against the real ralphex engine** (`umputun/ralphex`,
  `pkg/plan/parse.go`), correcting three inaccuracies carried over from the llm-kit
  template:
  - `### Iteration N:` is documented as an accepted token alongside `### Task N:`.
  - "task number from 1" reframed as an ordering convention, not a parser requirement
    (engine parses numbers with `strconv.Atoi`; non-integers become task `0`).
  - Title language clarified as irrelevant to the parser — only the literal
    `Task`/`Iteration` keyword and the colon are load-bearing.
  - Added engine facts: indented checkboxes are valid, `##`/h1-after-title close a task
    (`###`/`####` do not), and checkbox text containing `[ ]`/`[x]` is treated as a
    format example and ignored for completion.
