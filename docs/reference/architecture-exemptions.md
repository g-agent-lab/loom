# Reference — architecture exemptions

> Documented, deliberate deviations from the [llm-kit](https://github.com/g-agent-lab/llm-kit)
> canon (`UNIVERSAL_CORE.md`). Each has a reason. New deviations go here.

| # | Deviation | Reason |
|---|---|---|
| 1 | **No stack-specific architecture enforcement** — no kind-based DAG, no 6 thresholds, no dep-cruiser / boundary / cross-module-import baselines, no `.cjs` gates, none of the 5 architecture skills, no `post-edit-lint` hook. | This is a Markdown/shell/JSON marketplace, not a TypeScript app. `detect-stack.sh` returns `unknown`; llm-kit ships overlays only for TypeScript. Only the **universal** half (docs/process discipline) applies. |
| 2 | **No `docs/modules/` directory.** | Each plugin's own `plugins/<name>/README.md` is its module doc. Duplicating into `docs/modules/` would violate the repo's single-source-of-truth principle and drift. |
| 3 | **`AGENTS.md` is a thin pointer to `CLAUDE.md`**, not an "operational subset synced with CLAUDE.md". | A pointer cannot drift from its target. There are no external (e.g. Codex) agents needing a separate operational contract here. |
| 4 | **umputun plugins are included by reference (`git-subdir`)**, never vendored. | Upstream ownership; they must track `umputun/cc-thingz`. `drift-guard.sh` fails if any are vendored into `plugins/`. |
| 5 | **The llm-kit canon is referenced by URL, not vendored as an `external/llm-kit` submodule.** | Only the universal docs discipline is applied (no `.cjs` gates / overlays are consumed locally), so a submodule would be unused weight and runs against the repo's own no-vendoring ethos. Cite `g-agent-lab/llm-kit` + section numbers instead. Revisit if local gates are ever adopted. |
| 6 | **Two changelog channels.** Root `CHANGELOG.md` is own-plugin-scoped (enforced by `version-sync.sh`); `docs/changelog/` is the rotated session journal from `SESSION.md`. | They serve different audiences (plugin consumers vs. project memory) and have different lifecycles. |

> The plan-layout note (formerly exemption #2 — "completed plans live in
> `plans/completed/`") was **resolved**, not deviated: completed plans now live in
> the ralphex-native `docs/plans/active/completed/`, so there is nothing to exempt.
