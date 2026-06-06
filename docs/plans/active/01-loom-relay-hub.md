# loom-relay — Cloudflare Worker hub for autopilot two-way Telegram control

## Overview

`loom-relay` is a **new, separate component** (its own repo, a Cloudflare Worker in
TypeScript) that becomes the **single Telegram consumer** for the bot: it owns the bot's
webhook, demultiplexes incoming commands per project, and serves them to machines through a
**remote MCP server** (boundary-pull, no daemon). It also relays status replies back to
Telegram.

Problem it solves: in-plugin Telegram polling is unsound for a shared multi-machine bot —
`getUpdates` offset/ack is **bot-wide per token**, returns only the earliest 100 unconfirmed
updates, and allows **only one consumer per token** (a second poller gets HTTP 409). A single
webhook-owning hub that dedups by `update_id` and routes per project is the documented-correct
pattern (deep research, 2026-06-06). `getUpdates` and webhooks are mutually exclusive on a
token; once the hub sets the webhook, no machine may poll the token.

How it integrates: `autopilot` (revised separately in `02-autopilot-v0.4.md`) becomes an
MCP client; at each plan boundary it calls the hub's `poll_commands` / `post_status` tools.
Outbound progress notifications stay direct via autopilot's `notify.sh` (`sendMessage` works
even with a webhook set); only command replies route through the hub.

## Acceptance Criteria

- A single Worker owns the bot webhook; `/tg/webhook` rejects bad `secret_token` (401),
  dedups by `update_id`, drops non-allowlisted `from.id` (200), maps topic→project, parses
  `/stop`/`/status`, and enqueues into the project Durable Object.
- `poll_commands(project, since, ack_through)` returns only commands with `id > ack_through`
  and `ts >= since`, in order; `post_status(project, text)` posts to the project's topic.
- `/mcp` is rejected unless a valid Cloudflare Access JWT (verified against team JWKS + `aud`)
  is present — not merely a present header.
- Durable Object state (queue, cursor, dedup-set) survives eviction/cold-start.
- All `vitest-pool-workers` tests green; no secret committed to the repo.
- The two sibling plans (autopilot-v0.4, infra-quality-ci) have already been revised to drop the
  dead `poll-commands.sh` design (see Context → sequencing); no cross-plan contradiction remains.

## Context (from discovery)

- **This plan documents a SEPARATE repo.** All `src/...` / config paths below are relative to
  the new `loom-relay` repo root (a sibling checkout, e.g. `/Users/gurgen/project_it/loom-relay/`).
  This plan file itself lives in `loom-marketplace/docs/plans/active/` for tracking.
- Stack: **Cloudflare Workers + TypeScript**, **Durable Objects** (per-project queue + cursor),
  `wrangler` for deploy, **Streamable HTTP** MCP transport, `vitest` + `@cloudflare/vitest-pool-workers`
  (Miniflare) for tests. This is NOT one of the llm-kit overlay stacks used by autopilot/kit.
- Related existing patterns (in `loom-marketplace`, for parity, not edited here):
  - `plugins/autopilot/skills/batch/scripts/notify.sh` — the git-origin normalization for the
    project key and the topic-map idea (`telegram-topics.conf`) are mirrored by the hub's
    topic→project mapping.
- Dependencies / sequencing:
  - This plan **supersedes** the in-plugin Telegram polling that an earlier draft of the sibling
    plans contained. Those plans have **already been revised** to match this design — no
    cross-plan contradiction remains: `02-autopilot-v0.4.md` now uses an MCP-client
    boundary call + `relay_control` and builds no `poll-commands.sh`/`_tg-resolve.sh`;
    `03-infra-quality-ci.md` dropped the `poll-commands.sh` bats SUT and the
    `require-plan-a.sh` gate (its bats now covers `notify.sh` instead).
  - Recommended implementation order: **this relay plan first** → revised autopilot v0.4 (its
    Feature 2 needs the hub deployed + the MCP server configured in the session at runtime) →
    infra/quality (independent, any order). Machine-side MCP wiring lives in the autopilot plan.
  - Telegram Bot API contracts (webhook `secret_token`, `update_id` dedup, `sendMessage` with
    `message_thread_id`) — primary-sourced and stable.

## Development Approach

- **Testing approach**: Regular (code first, then tests). Each task ends by writing/updating
  `vitest-pool-workers` tests that run in the local Workers runtime (Miniflare); all green
  before the next task.
- Small, focused changes; complete each task fully first.
- **CRITICAL**: never commit secrets. Bot token, webhook `secret_token`, and the user-id
  allowlist are `wrangler secret put` values; `PROJECT_ROUTES` is a plain JSON env var. The
  machine-side Access credentials (`CF-Access-Client-Id`/`CF-Access-Client-Secret`) are never in
  this repo — they live in the machine's env / `.mcp.json` via `${...}` expansion (autopilot plan).
- **CRITICAL**: the webhook handler must return `200` fast and defer heavy work to
  `ctx.waitUntil` — otherwise Telegram redelivers (at-least-once).
- Keep handlers idempotent: dedup by `update_id`; `poll_commands` acks only what the caller
  reports handled.

## Testing Strategy

- **unit tests**: `vitest` via `@cloudflare/vitest-pool-workers` (real Workers runtime +
  Durable Objects). Cover secret_token validation, `update_id` dedup, allowlist authz,
  topic→project mapping, command parsing, DO enqueue/poll/ack, `since` filter, and
  `post_status`→Telegram `sendMessage` (mock outbound `fetch`).
- **integration smoke** (manual / Post-Completion): `wrangler dev` end-to-end —
  webhook → DO → `poll_commands` → ack; `post_status` → `sendMessage`.
- **e2e**: none (no UI).

## Progress Tracking

- mark `[x]` immediately when done; ➕ for new tasks; ⚠️ for blockers; keep in sync.

## Solution Overview

A single Worker with two ingress surfaces and one storage primitive:

- **Ingress 1 — `POST /tg/webhook`**: Telegram → hub. Validates `secret_token`, dedups, authz,
  maps topic→project, parses command, enqueues into the project's Durable Object.
- **Ingress 2 — `/mcp`**: machine → hub, gated by **Cloudflare Access** (zero-trust). Exposes
  `poll_commands(project, since, ack_through)`, `ack_commands(project, ack_through)`, and
  `post_status(project, text)`.
- **Storage — per-project Durable Object** (`ProjectQueue`): strongly-consistent FIFO command
  queue + acked cursor + `update_id` dedup set. Chosen over KV (eventual consistency → risk of
  double-serve) and Queues (async fan-out, overkill).

Routing key = normalized git origin remote (identical across machines that cloned the repo).
`PROJECT_ROUTES` maps each project to its `{chat_id, message_thread_id}`; the webhook
reverse-matches the incoming `(chat_id, topic)` to the project, and `post_status` looks the
route back up for replies.

- **`ProjectQueue` Durable Object** — pinned field contract (this is the exact contract the
  autopilot MCP client must consume):
  - `id` = Telegram `update_id` (monotonic, bot-wide); `ts` = Telegram `message.date` (epoch
    **seconds**, NOT server-receive time — avoids clock-skew/redelivery drift); `cmd` ∈
    `{stop, status}`; `from` = `message.from.id`.
  - `enqueue({id, cmd, from, ts})` dedups on `id` (ignore if `id` already in the seen-set).
  - `poll({since, ack_through})`: first **drop all queued entries with `id <= ack_through`**
    (cursor advance), then return remaining entries with `ts >= since`, in ascending `id`
    order. (`since` = the caller's `queue_start_epoch`, in seconds.)
  - **State hydration:** load `{queue, ackedCursor, seenSet}` from `this.ctx.storage` before
    serving — either via `blockConcurrencyWhile(() => hydrate())` in the constructor, or
    read-through on each method. REQUIRED so a freshly-rehydrated (evicted then woken) DO never
    serves a `poll`/`enqueue` against empty in-memory state — that would break dedup/idempotency.
- **`/tg/webhook` flow**: header `X-Telegram-Bot-Api-Secret-Token` must equal `TELEGRAM_SECRET_TOKEN`
  → **401** otherwise (genuine auth failure / misconfiguration); parse update; if `update_id`
  already seen → 200 no-op; extract `message.chat.id`, `message.message_thread_id` (topic),
  `message.from.id`, `message.text`, `message.date` (→ `ts`); if `from.id ∉ ALLOWLIST` → **200
  drop** (intentionally 200, NOT 403: prevents Telegram redelivery storms and does not leak
  allowlist state); resolve project by **reverse-matching** `(chat.id, message_thread_id)` against `PROJECT_ROUTES`; parse `/stop`, `/status` (also
  `@bot` and bare) → unknown ignored (200); `enqueue` into the project DO; return 200; heavy
  work in `ctx.waitUntil`.
- **MCP server transport** (pinned): **stateless Streamable HTTP** at `/mcp` using
  `@modelcontextprotocol/sdk`'s server with a thin Workers `fetch` adapter that returns JSON
  responses (no SSE session, no `Mcp-Session-Id` state). **Three tools:**
  - `poll_commands(project, since, ack_through)` → project DO `poll`.
  - `ack_commands(project, ack_through)` → project DO advances the acked cursor past
    `ack_through` (drops `id <= ack_through`) and returns nothing. Lets the client confirm a
    handled batch **without** fetching more — needed for the terminal `/stop`/final-boundary case
    where there is no "next poll" to ride the ack on (otherwise handled commands stay durable).
  - `post_status(project, text)` → resolve the project's route from `PROJECT_ROUTES`
    (`project → {chat_id, message_thread_id}`) and call Telegram `sendMessage`; if the project is
    unmapped, return a clear error (do not silently drop).
  **Deliberately stateless → NO second Durable Object.** (Cloudflare's `McpAgent`/`agents` SDK is
  the alternative but it backs sessions with its own DO + extra migration; rejected here to keep
  exactly one DO class. If a future feature needs server→client streaming, revisit.)
- **Routing/secrets**: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_SECRET_TOKEN`, `ALLOWLIST` (comma list of
  numeric user ids) via `wrangler secret put`. **`PROJECT_ROUTES`** is a **plain JSON env var**
  mapping `project → {chat_id, message_thread_id}` — this single map serves BOTH directions:
  webhook intake **reverse-matches** the incoming `(chat.id, message_thread_id)` to a project,
  and `post_status` looks up the project's `{chat_id, message_thread_id}` for the reply. (Plain
  var, not KV — a handful of projects.) `/mcp` is gated by **verifying the Cloudflare Access
  JWT**: fetch the team JWKS (`https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`, cached),
  verify the `Cf-Access-Jwt-Assertion` signature AND the `aud` claim against the Access app's AUD
  tag — **header presence is NOT sufficient** (a public Worker URL would otherwise be spoofable).
  The Worker verifies ONLY the Access-**injected** `Cf-Access-Jwt-Assertion`; the machine client
  authenticates by sending Access **service-token** headers (`CF-Access-Client-Id` +
  `CF-Access-Client-Secret`) which Cloudflare Access validates at the edge before injecting the
  assertion — the client never fabricates the assertion header itself.

## What Goes Where

- **Implementation Steps** (`[ ]`): Worker code, tests, in-repo docs.
- **Post-Completion** (no checkboxes): actual `wrangler deploy`, `setWebhook` call, Cloudflare
  Access application setup in the CF dashboard, populating real secrets, and the live phone
  smoke test — all require the operator's Cloudflare account and the real bot token.

## Implementation Steps

### Task 1: Scaffold loom-relay repo + wrangler + test harness

**Files:**
- Create: `package.json`
- Create: `wrangler.toml`
- Create: `tsconfig.json`
- Create: `vitest.config.ts`
- Create: `src/index.ts`
- Create: `test/health.test.ts`

- [ ] init the separate `loom-relay` repo (git init) with `package.json` (deps: `wrangler`, `typescript`, `vitest`, `@cloudflare/vitest-pool-workers`, **`@modelcontextprotocol/sdk`** for the MCP server, **`jose`** for CF Access JWT/JWKS verification)
- [ ] write `wrangler.toml` declaring the Worker, **exactly one** Durable Object class (`ProjectQueue`) + its migration, and a plain `PROJECT_ROUTES` JSON var (`project → {chat_id, message_thread_id}`; no KV binding; MCP is stateless → no session DO); `tsconfig.json`; `vitest.config.ts` wired to `@cloudflare/vitest-pool-workers`
- [ ] create minimal `src/index.ts` fetch handler responding `200` on `GET /health`
- [ ] write `test/health.test.ts` asserting `/health` → 200 (proves the Miniflare harness runs)
- [ ] run `npm test` — green before Task 2

### Task 2: ProjectQueue Durable Object (queue + cursor + dedup + since)

**Files:**
- Create: `src/durable-objects/project-queue.ts`
- Modify: `src/index.ts`
- Create: `test/project-queue.test.ts`

- [ ] implement `ProjectQueue` DO with the pinned field contract (Technical Details): `enqueue({id, cmd, from, ts})` dedup on `id`; `poll({since, ack_through})` = drop `id <= ack_through`, then return `ts >= since` in ascending-`id` order; `ack({ack_through})` = drop `id <= ack_through`, return nothing (backs the `ack_commands` tool's terminal-case confirm)
- [ ] persist `{queue, ackedCursor, seenSet}` in `this.ctx.storage` AND hydrate it before serving (`blockConcurrencyWhile` in the constructor or read-through per method); wire the DO class export in `src/index.ts`
- [ ] write tests: enqueue then poll returns it; duplicate `id` enqueue ignored; `ack_through` drops acked (`id <=`); `ack({ack_through})` advances cursor without returning; `since` drops stale; ordering is ascending `id`
- [ ] write tests for empty-state, re-poll-after-ack (idempotency), AND **state survival across a simulated DO restart** (vitest-pool-workers `runInDurableObject` / instance disposal) — proves hydration
- [ ] run `npm test` — green before Task 3

### Task 3: Telegram webhook endpoint (/tg/webhook)

**Files:**
- Create: `src/webhook.ts`
- Modify: `src/index.ts`
- Create: `src/lib/routes.ts`
- Create: `test/webhook.test.ts`

- [ ] implement `POST /tg/webhook`: validate `X-Telegram-Bot-Api-Secret-Token` (401 on mismatch); parse update; dedup by `update_id`; authz `from.id` against `ALLOWLIST`; resolve project by reverse-matching `(chat.id, message_thread_id)` via `src/lib/routes.ts`; parse `/stop`,`/status` (+`@bot`/bare); `enqueue` to the project DO; return 200; defer heavy work via `ctx.waitUntil`
- [ ] implement `routes.ts` parsing the plain `PROJECT_ROUTES` JSON var, exposing both directions: `routeFor(project) → {chat_id, message_thread_id}` (for `post_status`) and `projectFor(chat_id, message_thread_id) → project` (for webhook intake); capture `message.date` as the enqueued `ts`
- [ ] write tests: wrong/missing secret_token → **401**; non-allowlisted `from.id` → **200 drop** (assert NOT 403, so Telegram won't redeliver); known topic maps to project + enqueues; `/stop`,`/status`,`@bot`,bare parsed; unknown text ignored
- [ ] write tests: duplicate `update_id` is a no-op; malformed update doesn't 500
- [ ] run `npm test` — green before Task 4

### Task 4: MCP server (/mcp) — poll_commands + ack_commands + post_status — behind Cloudflare Access

**Files:**
- Create: `src/mcp.ts`
- Modify: `src/index.ts`
- Create: `src/lib/cf-access.ts`
- Create: `test/mcp.test.ts`

- [ ] implement a **stateless** Streamable HTTP MCP server at `/mcp` using `@modelcontextprotocol/sdk` + a thin Workers `fetch` adapter (JSON responses, no SSE session, no extra DO), exposing `poll_commands(project, since, ack_through)` (→ project DO `poll`), `ack_commands(project, ack_through)` (→ project DO `ack`), and `post_status(project, text)` (→ resolve `PROJECT_ROUTES[project]` `{chat_id, message_thread_id}`, then Telegram `sendMessage`; error if project unmapped)
- [ ] implement `src/lib/cf-access.ts` (using `jose`) that **verifies the Access-injected CF Access JWT** — fetch team JWKS (cached), verify `Cf-Access-Jwt-Assertion` signature AND `aud` claim against the app's AUD tag; reject on missing/invalid/aud-mismatch (header presence alone is NOT enough). The client presents `CF-Access-Client-Id`/`CF-Access-Client-Secret`; the Worker does NOT trust those directly — only the edge-injected assertion
- [ ] write tests: `poll_commands` returns/acks via the DO; `ack_commands` advances the cursor (a subsequent poll omits the acked ids); `post_status` calls Telegram `sendMessage` with the resolved `chat_id`+`message_thread_id` (mock outbound `fetch`, assert payload shape) and errors on an unmapped project; tool input schemas validate
- [ ] write tests: `/mcp` rejected with no JWT, bad-signature JWT, and wrong-`aud` JWT (mock the JWKS endpoint); accepted with a valid Access-injected assertion
- [ ] run `npm test` — green before Task 5

### Task 5: Secrets/config wiring + setup documentation

**Files:**
- Create: `README.md`
- Create: `docs/SETUP.md`
- Modify: `wrangler.toml`

- [ ] document secrets via `wrangler secret put` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_SECRET_TOKEN`, `ALLOWLIST`) and the `PROJECT_ROUTES` plain JSON env var (`project → {chat_id, message_thread_id}`) in `wrangler.toml`; ensure no secret is committed
- [ ] write `docs/SETUP.md`: create the bot, `setWebhook` with `secret_token`, `wrangler deploy`, create the Cloudflare Access application for `/mcp` + issue a **service token**, fill allowlist + `PROJECT_ROUTES`, and how a machine adds the MCP server to `.mcp.json` sending `CF-Access-Client-Id`/`CF-Access-Client-Secret` headers via `${...}` env-expansion (no secret committed; cross-link the autopilot plan)
- [ ] write `README.md` (what loom-relay is, architecture, link to SETUP)
- [ ] verify docs reference only `wrangler`/`jq`-level tooling and contain no real secrets
- [ ] run `npm test` — green before Task 6

### Task 6: Verify acceptance criteria

- [ ] all Overview requirements implemented (single webhook consumer; per-project DO; MCP `poll_commands`/`post_status`; CF Access gate; allowlist; `secret_token`; `since`/`update_id` dedup)
- [ ] run full `npm test` (vitest-pool-workers) — all green
- [ ] `wrangler dev` smoke: simulate a webhook → DO enqueue → `poll_commands` returns it → ack removes it; `post_status` → mocked/real `sendMessage`
- [ ] confirm (unit-level) secret_token mismatch → 401, non-allowlisted user → 200 drop, and the in-Worker CF Access JWT verification rejects no/bad/wrong-`aud` tokens. NOTE: true edge enforcement by Cloudflare Access is only observable post-deploy (`wrangler dev` does not run the Access edge) — verified in Post-Completion
- [ ] confirm no secrets are present in the repo (`git grep` for token-like strings)

### Task 7: Update documentation

- [ ] finalize `README.md`/`docs/SETUP.md` in the relay repo
- [ ] add a note in `loom-marketplace` `CLAUDE.md`/`README.md` that two-way Telegram control lives in the separate `loom-relay` component (cross-reference)
- [ ] move this plan to `docs/plans/completed/` (skip if executed via autopilot — it auto-moves on success)

## Post-Completion

*Items requiring the operator's Cloudflare account / real credentials — no checkboxes.*

**Manual / external setup:**
- `wrangler deploy` to the operator's Cloudflare account on `relay.<domain>`.
- Call Telegram `setWebhook` with the deployed URL + `secret_token` (note: this disables
  `getUpdates` on the token — `deleteWebhook` to revert).
- Create the Cloudflare Access application protecting `/mcp` and issue the machine service token.
- Populate real secrets (`wrangler secret put`) and the `PROJECT_ROUTES` map.
- Live phone smoke: run a 2-plan autopilot queue (after the autopilot v0.4 revision lands),
  send `/status` and `/stop` in the project topic, confirm reply + graceful halt.

**Related plans (revisions already applied):**
- `02-autopilot-v0.4.md`: machine-side MCP client wiring (`poll_commands`/`post_status` at
  plan boundary), `relay_control` userConfig, no `poll-commands.sh`.
- `03-infra-quality-ci.md`: bats covers `notify.sh` (not `poll-commands.sh`); no
  `require-plan-a.sh` gate; plan is independent.
