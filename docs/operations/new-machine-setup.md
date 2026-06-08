# Operations — new-machine setup

> Operator runbook. Bring the full loom toolchain up on a second machine —
> plugins, Telegram notifications, and `autopilot`'s two-way control — pointing at
> the **existing** `loom-relay` hub. Companion to
> [`marketplace-management.md`](marketplace-management.md).

## Model — one hub, many clients

`loom-relay` is a **single shared** Cloudflare Worker (`relay.gurgen.dev`), not a
per-machine install. It owns the Telegram bot's one webhook, so there is exactly
one relay per bot. A new machine is another **client** of it — you never deploy a
second relay. (Telegram allows a single webhook per bot token; a second relay
would steal it from the first.) Background:
[`../CONTEXT.md`](../CONTEXT.md) and
[`../../plugins/autopilot/references/relay-control.md`](../../plugins/autopilot/references/relay-control.md).

Three layers, set up in order:

| Layer | What you do |
|---|---|
| Plugins (marketplace) | install from git — nothing is copied |
| Telegram notify (one-way) | copy 2 config files, change only the label |
| Two-way control (MCP client) | helper + CF-Access service token + one `~/.claude.json` entry |

## Prerequisites

- `claude` CLI, `git`, `python3`, `curl` on the new machine (Homebrew, per the
  global package rules).
- Access to the **old** machine's files (to copy two Telegram configs + the MCP
  helper), or: the bot token and a way to mint a Cloudflare Access service token.

## 1. Plugins

```
claude plugin marketplace add g-agent-lab/loom        # once per machine
claude plugin install autopilot@loom
claude plugin install kit@loom
claude plugin install slicer@loom
# umputun set, as wanted:
claude plugin install planning@loom review@loom brainstorm@loom \
  release-tools@loom thinking-tools@loom skill-eval@loom workflow@loom
```

`claude plugin list` should then show them `enabled`. Versions come from git — no
file copying. (Prefer the CLI over the `/plugin` UI for operator steps.)

## 2. Telegram notifications (one-way progress)

Copy the two per-machine config files into the new machine's autopilot data dir.
The dir is named after the install: a marketplace install of `autopilot@loom`
resolves `~/.claude/plugins/data/autopilot-loom/`.

From the **old** machine:

```
scp ~/.claude/plugins/data/autopilot-loom/telegram.conf \
    ~/.claude/plugins/data/autopilot-loom/telegram-topics.conf \
    <new-host>:~/.claude/plugins/data/autopilot-loom/
```

Then on the new machine change **only** the label in `telegram.conf`:

```
TELEGRAM_LABEL=work        # was: home — distinguishes machines in the chat
```

Bot token, chat id, and the topic map are **shared** (same bot, same supergroup,
topics keyed by normalized git origin), so they copy as-is. Detail:
[`../../plugins/autopilot/references/telegram-setup.md`](../../plugins/autopilot/references/telegram-setup.md) §5.

## 3. Two-way control (`/stop` · `/status` via loom-relay MCP)

Three pieces: a CF-Access **service token**, the **headers helper**, and the
**MCP server entry**. The entry must be named exactly `loom-relay` — the skill's
`allowed-tools` reference `mcp__loom-relay__*` statically, so any other name is a
silent no-op (looks identical to "not configured"). Contract:
[`../reference/contracts.md`](../reference/contracts.md).

### 3a. Service token — mint a new one (recommended)

Each machine should carry its **own** Cloudflare Access service token, so you can
revoke one machine without touching the other.

1. Zero Trust dashboard → **Access → Service Auth → Service Tokens → Create** →
   name it per machine (e.g. `loom-relay-work`). Copy the **Client ID** and
   **Client Secret** (the secret is shown once).
2. If the relay's Access application policy lists **specific** tokens (rather than
   "any service token"), add the new token to that policy — otherwise it is
   refused at the edge.
3. On the new machine, save it where the helper expects:

   ```
   mkdir -p ~/.config/loom-relay && chmod 700 ~/.config/loom-relay
   cat > ~/.config/loom-relay/service-token.json <<'JSON'
   { "client_id": "<CLIENT_ID>.access", "client_secret": "<CLIENT_SECRET>" }
   JSON
   chmod 600 ~/.config/loom-relay/service-token.json
   ```

   The helper accepts a flat `{client_id, client_secret}` or the full Cloudflare
   API response shape (`result.client_id`, …) — the minimal flat form above is
   enough.

**Quick alternative — reuse the old machine's token:** copy
`~/.config/loom-relay/service-token.json` verbatim. Simpler, but both machines
then share one credential, so revoking it cuts off both.

### 3b. Headers helper

Copy the helper from the old machine — it carries no secret, it only reads the
JSON from 3a:

```
scp ~/.config/loom-relay/headers.sh <new-host>:~/.config/loom-relay/headers.sh
chmod 700 ~/.config/loom-relay/headers.sh
```

### 3c. MCP server entry

Register the relay at **user scope** (global across projects). Add this block to
`~/.claude.json` under `mcpServers` — the helper path must be absolute:

```jsonc
"loom-relay": {
  "type": "http",
  "url": "https://relay.gurgen.dev/mcp",
  "headersHelper": "bash /Users/<you>/.config/loom-relay/headers.sh"
}
```

Disable control later with `claude mcp remove loom-relay` — the server's presence
*is* the on/off switch.

## 4. Verify

```
# helper emits both Access headers as JSON
bash ~/.config/loom-relay/headers.sh

# edge: no creds → 403 (Access up); with creds → 405 (GET on a POST-only /mcp = auth OK)
curl -s -o /dev/null -w '%{http_code}\n' https://relay.gurgen.dev/mcp

# in a Claude session the relay connects and exposes mcp__loom-relay__* tools
claude mcp list
```

Then run `/autopilot:run` on a real project and send `/status` in its Telegram
topic — a `📊 [N/M] …` reply confirms the full round trip.

## Do NOT copy (relay-admin only)

These live in `~/.config/loom-relay/` on the deploy machine and exist to
**manage** the Worker, not to use it. Skip them unless the new machine will
deploy/redeploy the relay:

- `cf.env` — `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN` /
  `TELEGRAM_SECRET_TOKEN` (wrangler + the Telegram webhook secret).
- `verify.sh` — CF diagnostics (needs `cf.env`).
- `mcp-env.sh` — the static-`headers` alternative; unused when you use
  `headersHelper`.

## New project ≠ new machine

Two-way control for a project needs a route on the **relay** (normalized git
origin → Telegram topic) — that is per-**project**, configured once on the Worker
(`PROJECT_ROUTES`), not per machine. For a project the relay already knows (route
+ a line in `telegram-topics.conf`), a new machine needs nothing extra. Adding a
brand-new project: add its route on the relay and a line in
`telegram-topics.conf`. Caveat: if two machines run `autopilot` on the **same**
repo at once, they share one command queue — `/stop` is consumed by whichever
polls first.
