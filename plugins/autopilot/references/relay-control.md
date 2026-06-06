# Two-way control via loom-relay

Point autopilot at a deployed [`loom-relay`](https://github.com/g-agent-lab/loom)
hub so you can drive a running queue from Telegram. This is the machine-side wiring;
the hub itself (webhook owner + per-project MCP relay) is a separate Cloudflare
Worker — see its `docs/plans/.../01-loom-relay-hub.md` and `docs/SETUP.md`.

## What it does

When the `loom-relay` MCP server is connected, the queue checks for commands **at
each plan boundary**. There is **no toggle** — the MCP server's presence *is* the
switch (configure it to enable, `claude mcp remove loom-relay` to disable):

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
   cannot call, and control then **silently does nothing** (looks identical
   to "not configured").

   **Recommended — `headersHelper` (launch-independent).** Point the entry at a
   small script that reads the service token from a local file and prints the
   headers as JSON. Because it reads a file (not the process env), control connects
   no matter how Claude Code was started (fresh terminal, stale terminal, IDE, GUI),
   and no secret lives in `.mcp.json`:

   ```jsonc
   {
     "mcpServers": {
       "loom-relay": {
         "type": "http",
         "url": "https://relay.<your-domain>/mcp",
         "headersHelper": "bash /absolute/path/to/loom-relay-headers.sh"
       }
     }
   }
   ```

   The helper (chmod 600, outside any repo) prints exactly one JSON object to stdout:

   ```bash
   #!/usr/bin/env bash
   # reads the service token saved at deploy time; emits the two Access headers
   exec python3 - <<'PY'
   import json, os
   d = json.load(open(os.path.expanduser('~/.config/loom-relay/service-token.json')))
   cid = d.get('client_id') or d.get('result', {}).get('client_id', '')
   sec = d.get('client_secret') or d.get('result', {}).get('client_secret', '')
   print(json.dumps({"CF-Access-Client-Id": cid, "CF-Access-Client-Secret": sec}))
   PY
   ```

   Cloudflare Access validates these service-token headers at the edge and injects
   the JWT the Worker verifies — the client never fabricates the assertion header.
   This is **not** a single bearer token.

   **Simpler alternative — static `headers` with env-expansion.** Use
   `"headers": { "CF-Access-Client-Id": "${LOOM_RELAY_CF_ACCESS_CLIENT_ID}", … }`
   and export both vars in the machine's environment. Works, but only when Claude
   Code is launched from a shell that has those vars exported — a stale terminal or
   a GUI launch will expand them to empty and auth will fail.
3. Make sure the relay's `PROJECT_ROUTES` includes this repo's key — the
   **normalized `git remote origin`** (same key `notify.sh` uses), not the repo
   basename — mapped to its Telegram topic.

## Notes

- **Latency.** Control is checked only between plans, so `/stop` takes effect after
  the plan currently running finishes — there is no mid-plan interruption.
- **Never blocks the queue.** Any MCP error or an unavailable/misnamed server is a
  silent no-op; the run continues exactly as if `loom-relay` were not configured.
- **Intake lives in the hub.** Dedup (`update_id`), the allowlist, and topic→project
  demux are all handled by `loom-relay`. autopilot only consumes its own project's
  queue. One-way progress via `notify.sh` is independent and unaffected.
