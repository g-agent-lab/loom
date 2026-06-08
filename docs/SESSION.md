# SESSION — loom marketplace

> Live session journal. Only the current session's entries live here. When this
> file exceeds 100 lines, rotate older entries into `changelog/YYYY-MM.md` per
> [`DOCS_RULES.md`](DOCS_RULES.md). This is separate from the own-plugin
> [`../CHANGELOG.md`](../CHANGELOG.md).

### [2026-06-08] llm-kit universal-core bootstrap (docs discipline)

- Files: `docs/CONTEXT.md`, `docs/DOCS_RULES.md`, `docs/SESSION.md`,
  `docs/plans/ROADMAP.md`, `docs/reference/*.md`,
  `docs/operations/marketplace-management.md`, `scripts/docs-lint.sh`,
  `tests/docs-lint.bats`, `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`.
- Change: (1) applied the **universal** half of llm-kit (`UNIVERSAL_CORE.md`
  §5/§6/§7) to the marketplace — created the `docs/` entry-point layer
  (CONTEXT/DOCS_RULES/SESSION/ROADMAP), the `reference/` docs (env-variables,
  contracts, module-routing, architecture-exemptions), and an operations runbook;
  (2) reframed `CLAUDE.md` into the 8-section agent contract, relocating the
  verbose "adding an umputun plugin" / "install-update" how-tos into
  `docs/operations/marketplace-management.md`; (3) added a `docs-lint` check
  script + bats test and wired it into CI; (4) moved the three completed plans
  from `docs/plans/completed/` to the ralphex-native `docs/plans/active/completed/`
  and removed the old dir — dropping the former plan-layout exemption (this is the
  path `autopilot`'s `mark-completed.sh` already writes to).
- Reason: bring the project to our llm-kit architectural/documentation standard.
  The stack-specific architecture-enforcement half (TS gates, dep-cruiser /
  boundary baselines, the 5 arch skills) was deliberately **skipped** — this is a
  Markdown/shell/JSON marketplace with no module graph (stack detected as
  `unknown`). Deviations recorded in
  `docs/reference/architecture-exemptions.md`.
