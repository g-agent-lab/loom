# loom marketplace — infrastructure & quality (Full)

## Overview

Establish a quality baseline for the public `loom` marketplace: fix the current
documentation drift, add validation/guard scripts that encode the repo's invariants
(CLAUDE.md conventions), add a bats unit-test suite for the shell scripts, and wire it all
into GitHub Actions so every push/PR is checked.

Problem solved: the marketplace is published publicly with 12+ shell scripts (that move
files, drive git worktrees, and hit the Telegram API) and **zero** automated tests or CI,
plus README/CHANGELOG that have drifted out of sync with the manifest (`slicer` missing).

This is the "Full" infra scope chosen in brainstorm: docs fix · manifest validation ·
shellcheck · umputun-drift guard · version-sync · link-check · bats · CI.

## Acceptance Criteria

- README and root `CHANGELOG.md` acknowledge all **three** own plugins (incl. `slicer`); the
  README plugin table lists 3 own + 7 umputun = 10 entries, matching `marketplace.json`.
- `scripts/validate-marketplace.sh`, `drift-guard.sh`, `version-sync.sh`, `link-check.sh` each
  exit 0 against the live repo and non-zero (with a clear message) against a deliberately broken
  fixture.
- `version-sync.sh` enforces BOTH modes: section-scoped static matching AND diff-aware bump
  enforcement (changed `plugins/<own>/**` ⇒ HEAD `version` is **semver-greater** than base —
  unchanged or downgraded FAILS — AND the new version string appears in that plugin's changelog
  section); with no base ref it falls back to static and logs that enforcement was skipped (never
  a silent pass).
- `bats tests/` is all green, covering `discover-plans.sh`, `mark-completed.sh`, `notify.sh`,
  `detect-stack.sh`, `detect-mode.sh`.
- `shellcheck` is clean over every tracked `*.sh`.
- `.github/workflows/ci.yml` is valid YAML, runs all checks + shellcheck + bats on push/PR, fails
  the build on any non-zero exit, and requires only CI-installable tooling (bash/jq/shellcheck/
  bats — no node/python).
- No umputun-referenced plugin files are modified.

## Context (from discovery)

- Files/components involved:
  - `README.md` — line 5 says "Two plugins of my own"; the plugin table (lines 25–35) omits `slicer`.
  - `CHANGELOG.md` (root) — lines 1–4 scope it to `autopilot, kit` only; no `slicer` section.
  - `plugins/slicer/CHANGELOG.md` — slicer's own changelog (source to sync/reference).
  - `.claude-plugin/marketplace.json` — manifest; 3 own (`autopilot`, `kit`, `slicer`) + 7 umputun via `git-subdir`.
  - `plugins/*/.claude-plugin/plugin.json` — own plugin manifests (name/version).
  - `scripts/` — **new** top-level home for the CHECK scripts only: `validate-marketplace.sh`, `drift-guard.sh`, `version-sync.sh`, `link-check.sh`.
  - `tests/` — currently empty **and untracked** (git does not track empty dirs); it materializes once the first `.bats`/`helpers.bash` is committed. **New** bats suite lives here.
  - **Scripts UNDER TEST live in nested plugin dirs, NOT in top-level `scripts/`:**
    - `plugins/autopilot/skills/batch/scripts/discover-plans.sh`
    - `plugins/autopilot/skills/batch/scripts/mark-completed.sh`
    - `plugins/autopilot/skills/batch/scripts/notify.sh` (token/chat/topic resolution + silent no-op)
    - `plugins/kit/skills/greenfield/scripts/detect-stack.sh`
    - `plugins/kit/skills/greenfield/scripts/detect-mode.sh`
  - `.github/workflows/ci.yml` — **new**.
  - NOTE: the autopilot v0.4 redesign (`01-loom-relay-hub.md`) moved Telegram command
    intake to the separate `loom-relay` Worker, so there is **no** `poll-commands.sh` /
    `_tg-resolve.sh` to test here, and **no** cross-plan ordering gate. The relay's own tests
    live in the relay repo. This plan is now independent of plan A.
- Related patterns found:
  - CLAUDE.md invariants to encode: own plugins are only `autopilot`/`kit`/`slicer`; umputun entries must stay `git-subdir` (no vendoring/drift); manifest is source of truth; versioning requires plugin.json bump + CHANGELOG entry; public prose is English-primary.
  - All scripts are POSIX-ish bash; `jq` is available locally and in CI.
- Dependencies identified:
  - **None on plan A.** The bats suite covers only pre-existing scripts (`discover-plans.sh`,
    `mark-completed.sh`, `notify.sh`, `detect-stack.sh`, `detect-mode.sh`). This plan can run
    independently and in any order relative to the autopilot v0.4 / loom-relay plans.

## Development Approach

- **Testing approach**: Regular (code first, then tests). Each check script is verified by
  running it against the live repo (expect pass) **and** against a deliberately-broken
  temporary fixture (expect fail) — that pass/fail pair is the script's test. The bats suite
  (Task 4) unit-tests the runtime shell scripts with fixtures.
- Small, focused commits; each task self-contained.
- **CRITICAL**: scripts must be tool-light — `bash` + `jq` + `grep`/`awk` only. No node/python required for CI to run.
- **CRITICAL**: never edit umputun-referenced plugins; the drift-guard exists precisely to prevent that.
- Local tooling via brew (`shellcheck`, `bats-core`, `jq`); CI installs via apt + the bats-core action.

## Testing Strategy

- **unit tests**: bats (`tests/*.bats`) for `discover-plans.sh`, `mark-completed.sh`,
  `notify.sh` (token/chat/topic resolution incl. sibling `autopilot-*` fallback + silent no-op
  when unconfigured), `detect-stack.sh`, `detect-mode.sh`. Check scripts are tested via their
  own pass/fail fixture runs (Tasks 2–3).
- **e2e tests**: none.

## Progress Tracking

- mark `[x]` immediately when done; ➕ for new tasks; ⚠️ for blockers; keep in sync.

## Solution Overview

- A `scripts/` directory of small, single-purpose check scripts, each runnable standalone
  and from CI, each exiting non-zero with a clear message on violation.
- A `tests/` bats suite for the runtime shell scripts, using temp-dir fixtures (fake repos,
  fake plan files, fake `telegram.conf`, stubbed `curl`).
- One `ci.yml` that installs tooling and runs: validate-marketplace → drift-guard →
  version-sync (diff-aware) → link-check → shellcheck → bats.

## Technical Details

- **`validate-marketplace.sh`**: `jq` over `marketplace.json` — top-level `name`/`owner`
  present; each own plugin (`source` is a string `./plugins/<x>`) has a dir with
  `.claude-plugin/plugin.json` whose `name` matches the manifest entry and has a non-empty
  `version`; each umputun entry has `source.source == "git-subdir"` and a `url`/`path`. Also
  assert no duplicate `name` keys and a non-empty `description` on every entry.
- **`drift-guard.sh`**: assert `plugins/` contains exactly `autopilot kit slicer` (no extra
  vendored dirs); assert no manifest entry for an umputun plugin uses a local `./plugins/...`
  source. Fail listing offenders.
- **`version-sync.sh`** — TWO distinct responsibilities, kept separate so the guard cannot give
  false confidence (a static "version appears in changelog" check does NOT enforce "a change
  requires a bump" — `0.3.1` keeps matching even after autopilot code changes):
  1. **Static consistency (always runs):** **section-scoped matching** (a bare grep is unsound —
     `0.1.0` appears under BOTH autopilot and kit in the root CHANGELOG, so a naive match
     cross-validates). For each own plugin, the `plugin.json` `version` must appear **within that
     plugin's own changelog section**: for autopilot/kit, the text between `## autopilot`/`## kit`
     and the next `## ` header in root `CHANGELOG.md` (extract with awk); for slicer, in
     `plugins/slicer/CHANGELOG.md`.
  2. **Diff-aware enforcement (when a base ref is available — i.e. CI):** this is what actually
     encodes the convention. Compute changed files vs base (`git diff --name-only $BASE...HEAD`).
     **`$BASE` resolution, in order:** (i) PR → the PR base SHA
     (`github.event.pull_request.base.sha`); (ii) push → `github.event.before` (the branch's prior
     tip) — REQUIRED so a **direct push to `master`** still diffs against the previous commit;
     treat the all-zero SHA (new branch / initial push / force-push with no parent) as "no base";
     (iii) last resort (local one-off) → `git merge-base origin/master HEAD`. **Do NOT** rely on
     `merge-base origin/master HEAD` for a push to `master`: there it resolves to HEAD's own
     ancestor and yields an effectively empty diff → enforcement would silently pass. `ci.yml`
     passes the resolved SHA into `version-sync.sh` as `$BASE`; the script uses `$BASE` when set,
     else falls back to the local merge-base. If ANY `plugins/<own>/**` file
     changed, REQUIRE: (a) the `.claude-plugin/plugin.json` `version` at HEAD is
     **semver-greater than** its value at `$BASE` — compare `git show $BASE:<path>` (jq the
     `version`) against HEAD (e.g. `sort -V` / a `major.minor.patch` numeric compare); a mere edit
     to `plugin.json` (e.g. a description tweak) with an **unchanged** `version` FAILS, and a
     **downgrade** FAILS (this is a hard requirement, not optional); AND (b) that **exact new
     version string appears in the plugin's changelog section** in the diff — bumping `version`
     without a matching changelog entry, OR adding an unrelated changelog line without the bump,
     FAILS. When no
     base ref is resolvable (local one-off), fall back to static mode and `log` that enforcement
     was skipped — never a silent pass.
  The guard keys off `plugins/<x>/` paths only — editing root README/CLAUDE.md must NOT trip it.
  Fail with the precise per-plugin mismatch.
- **`link-check.sh`**: extract relative markdown links from README + plugin READMEs + `docs/`
  (excluding `docs/plans/`, which cross-reference transient plan files) and assert each target
  path exists in-repo. Skip `http(s)://`, `mailto:`, and pure `#anchor` links. Fail listing
  dead links.
- **bats**: temp `BATS_TMPDIR` fixtures; stub network by shimming `curl` on `PATH` for
  `notify.sh`'s `sendMessage` path.
- **`ci.yml`**: `ubuntu-latest`; `apt-get install -y shellcheck jq`; `bats-core/bats-action`
  (or `npm i -g bats` fallback); run scripts; `shellcheck $(git ls-files '*.sh')`; `bats tests`.

## What Goes Where

- **Implementation Steps** (`[ ]`): doc fixes, scripts, tests, workflow.
- **Post-Completion** (no checkboxes): observing the first green CI run on GitHub; enabling
  branch protection requiring the check.

## Implementation Steps

### Task 1: Fix documentation drift (slicer)

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] README: change "Two plugins of my own" → three (`autopilot`, `kit`, `slicer`); add a `slicer` row to the Plugins table with the correct description and `own` origin
- [x] CHANGELOG.md: broaden the header scope sentence to acknowledge `slicer`, and add a `## slicer` section that **references** `plugins/slicer/CHANGELOG.md` as slicer's source of truth (a pointer line + link) — do NOT duplicate slicer's entries into the root file (one source of truth; duplication would re-introduce drift). `version-sync.sh` validates slicer against `plugins/slicer/CHANGELOG.md`, consistent with this
- [x] verify: README plugin table lists all 3 own + 7 umputun = 10 entries, matching `marketplace.json`
- [x] write check: a quick grep assertion that `slicer` appears in the README table and the root CHANGELOG header/pointer — must pass before Task 2

### Task 2: validate-marketplace.sh

**Files:**
- Create: `scripts/validate-marketplace.sh`

- [ ] implement `jq`-based validation of `marketplace.json` (top-level fields; own plugins resolve to a dir + matching `plugin.json` name + non-empty version; umputun entries are `git-subdir`)
- [ ] exit non-zero with a precise message per violation; exit 0 when clean
- [ ] verify: `shellcheck scripts/validate-marketplace.sh` clean
- [ ] test (pass case): run against the real repo → exit 0
- [ ] test (fail case): run against a temp copy with a broken entry (missing version / vendored umputun) → non-zero with the expected message — must pass before Task 3

### Task 3: Guard scripts — drift, version-sync, link-check

**Files:**
- Create: `scripts/drift-guard.sh`
- Create: `scripts/version-sync.sh`
- Create: `scripts/link-check.sh`

- [ ] implement `drift-guard.sh` (plugins/ == exactly autopilot+kit+slicer; umputun entries stay git-subdir)
- [ ] implement `version-sync.sh` with BOTH modes (see Technical Details): (1) **static** section-scoped matching — autopilot/kit versions checked within their own `## <plugin>`→next-`## ` block in root `CHANGELOG.md` (awk-extracted), slicer in `plugins/slicer/CHANGELOG.md`; (2) **diff-aware enforcement** when a base ref exists — if `plugins/<own>/**` changed vs base, REQUIRE the HEAD `plugin.json` `version` to be **semver-greater than base** (unchanged or downgraded FAILS) AND a changelog line containing that exact new version under the plugin's section (else fall back to static and `log` that enforcement was skipped). Key off `plugins/<x>/` paths only
- [ ] implement `link-check.sh` (relative markdown links resolve in-repo; skip `http(s)://`, `mailto:`, `#anchor`; exclude `docs/plans/`)
- [ ] verify: `shellcheck` clean on all three
- [ ] test (pass): all three exit 0 against the real repo
- [ ] test (fail): temp fixtures — a vendored `plugins/brainstorm/`; a kit version present only in autopilot's CHANGELOG section (proves section-scoping rejects the cross-section false match); a simulated diff where `plugins/autopilot/**` changed but `plugin.json` `version` did NOT (diff-aware fails it); a diff that bumps `version` but adds **no** changelog line containing that new version (fails); a diff that bumps `version` AND adds a matching changelog line (passes — the positive control); a diff that *downgrades* `version` (fails the required semver-greater check); a dead relative link — each produces the expected exit + clear message — must pass before Task 4

### Task 4: bats unit-test suite for shell scripts

**Files (to Create):**
- `tests/helpers.bash`
- `tests/discover-plans.bats` — SUT: `plugins/autopilot/skills/batch/scripts/discover-plans.sh`
- `tests/mark-completed.bats` — SUT: `plugins/autopilot/skills/batch/scripts/mark-completed.sh`
- `tests/notify.bats` — SUT: `plugins/autopilot/skills/batch/scripts/notify.sh`
- `tests/kit-detect.bats` — SUT: `plugins/kit/skills/greenfield/scripts/{detect-stack.sh,detect-mode.sh}`

- [ ] install the bats harness locally: `brew install bats-core` (hard prerequisite for this task's own pass gate)
- [ ] add `tests/helpers.bash` with temp-dir setup/teardown and a `curl` PATH-stub helper; have each `.bats` reference its SUT by the full nested path above
- [ ] write bats for `discover-plans.sh` (sorts, excludes `completed/`, skips non-runnable plans) and `mark-completed.sh` (moves into `completed/`, lazy-creates subdir)
- [ ] write bats for `notify.sh`: token/chat/topic resolution (env → `telegram.conf` → sibling `autopilot-*` fallback → topic map by normalized origin), silent no-op + `exit 0` when unconfigured, and the `sendMessage` payload shape (stubbed `curl`)
- [ ] write bats for `detect-stack.sh` and `detect-mode.sh` (greenfield vs brownfield signals; known-stack detection)
- [ ] `git add` the new `tests/` files (CI only sees tracked files), then run `bats tests/` locally — all green — must pass before Task 5

### Task 5: shellcheck wiring + GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] author `ci.yml` (push + PR): checkout with `fetch-depth: 0` (so version-sync's diff-aware mode has a base ref); resolve and export `$BASE` for version-sync — PR → `github.event.pull_request.base.sha`, push → `github.event.before` (NOT `merge-base origin/master HEAD`, which is empty on a direct push to `master`); install `shellcheck`/`jq`/`bats`; run validate-marketplace, drift-guard, version-sync (diff-aware in CI, passing `$BASE`), link-check; `shellcheck` over all tracked `*.sh`; `bats tests/`
- [ ] ensure the job fails the build on any check's non-zero exit; name steps clearly
- [ ] verify: `shellcheck $(git ls-files '*.sh')` is clean locally (fix any residual findings in existing scripts)
- [ ] test: run the exact CI command sequence locally (or via `act` if available) — all steps pass — must pass before Task 6

### Task 6: Verify acceptance criteria

- [ ] verify every Acceptance Criteria item (top of plan) is met
- [ ] run every check script against the repo → all exit 0
- [ ] run `bats tests/` → all green
- [ ] run `shellcheck` over all tracked `*.sh` → clean
- [ ] confirm `ci.yml` is valid YAML and references only tooling installable in CI (no node/python requirement)
- [ ] confirm no umputun-referenced files were modified (`git status`)

### Task 7: Update documentation

- [ ] README: add a short "Development / CI" section (how to run checks + tests locally via brew tooling)
- [ ] CLAUDE.md: add the new conventions (run `scripts/*` + `bats tests/` before pushing; CI enforces drift/version/link guards)
- [ ] move this plan to `docs/plans/completed/` (skip if executed via autopilot — it auto-moves on success)

## Post-Completion

**Manual verification:**
- Push a branch and confirm the GitHub Actions run is green; intentionally break one
  invariant in a throwaway commit to confirm CI fails as designed.

**External system updates:**
- Optionally enable branch protection on `master` requiring the CI check to pass before merge.
