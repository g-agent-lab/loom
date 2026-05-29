# Changelog

All notable changes to the **own** plugins (`autopilot`, `kit`) are recorded here.
The umputun plugins are referenced from upstream and versioned there, not here.

## autopilot

### 0.2.0 — 2026-05-29
- Renamed from `queue` to `autopilot` as part of the `loom` marketplace launch.
- Pre-flight idempotent success check: a plan already fully `[x]` on entry is
  treated as success and moved to `completed/` without re-running `/planning:exec`.
- Bilingual skill triggers (English + Russian).

### 0.1.0
- Initial sequential plan runner: discover plans in `docs/plans/active/`, run each
  through `/planning:exec`, verify checkboxes, move to `completed/`, loop.

## kit

### 0.1.0 — 2026-05-29
- Initial release in the `loom` marketplace (formerly standalone `cc-kit`).
- Greenfield + brownfield llm-kit bootstrap driver; reads the llm-kit playbook live.
- Bilingual skill triggers (English + Russian).
