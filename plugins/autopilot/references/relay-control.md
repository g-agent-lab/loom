# Two-way control via loom-relay

Point autopilot at a deployed [`loom-relay`](https://github.com/g-agent-lab/loom)
hub so you can drive a running queue from Telegram. This is the machine-side wiring;
the hub itself (webhook owner + per-project MCP relay) is a separate Cloudflare
Worker — see its `docs/plans/.../01-loom-relay-hub.md` and `docs/SETUP.md`.

## What it does

With `relay_control: true` (autopilot userConfig, default `false`) and the
`loom-relay` MCP server connected, the queue checks for commands **at each plan
boundary**:

- **`/status`** — replies in the project's Telegram topic with live counters
  (`📊 [N/M] ok:<c> fail:<f> skip:<s>`). Does not change control flow.
- **`/stop`** — graceful halt: finishes nothing new, marks the remaining plans
  skipped, replies `🛑 stopped by command`, and ends the run after the current
  plan.

Commands are **plan-boundary only** — never mid-plan. A command sent during the
last plan is still answered by a final checkpoint before the summary.

## Setup

1. Deploy `loom-relay` and issue a Cloudflare Access **service token** for this
   machine (see the hub's `docs/SETUP.md`).
2. Add the MCP server to the machine's `.mcp.json`. **The entry MUST be named
   exactly `loom-relay`** — the skill's `allowed-tools` reference
   `mcp__loom-relay__*` statically, so any other name yields tools the skill
   cannot call, and `relay_control` then **silently does nothing** (looks identical
   to "not configured"). Pass the Access service-token headers via `${...}`
   env-expansion so no secret lands in the repo:

   ```jsonc
   {
     "mcpServers": {
       "loom-relay": {
         "type": "http",
         "url": "https://relay.<your-domain>/mcp",
         "headers": {
           "CF-Access-Client-Id": "${LOOM_RELAY_CF_ACCESS_CLIENT_ID}",
           "CF-Access-Client-Secret": "${LOOM_RELAY_CF_ACCESS_CLIENT_SECRET}"
         }
       }
     }
   }
   ```

   Export `LOOM_RELAY_CF_ACCESS_CLIENT_ID` / `LOOM_RELAY_CF_ACCESS_CLIENT_SECRET`
   in the machine's environment (e.g. your shell profile). Cloudflare Access
   validates these at the edge and injects the JWT the Worker verifies — the client
   never fabricates the assertion header. This is **not** a single bearer token.
3. Set autopilot's `relay_control` userConfig to `true`.
4. Make sure the relay's `PROJECT_ROUTES` includes this repo's key — the
   **normalized `git remote origin`** (same key `notify.sh` uses), not the repo
   basename — mapped to its Telegram topic.

## Notes

- **Latency.** Control is checked only between plans, so `/stop` takes effect after
  the plan currently running finishes — there is no mid-plan interruption.
- **Never blocks the queue.** Any MCP error or an unavailable/misnamed server is a
  silent no-op; the run continues exactly as if `relay_control` were off.
- **Intake lives in the hub.** Dedup (`update_id`), the allowlist, and topic→project
  demux are all handled by `loom-relay`. autopilot only consumes its own project's
  queue. One-way progress via `notify.sh` is independent and unaffected.
