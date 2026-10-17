# Discord gateway

Official docs: [Messaging gateway](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/) · [Discord](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord)

This document records **findings** for adding Discord alongside Telegram on this Hermes VPS setup, **manual steps you must finish before repo automation**, multi-platform consequences, and Discord limits (including whether you need a paid plan).

**Status (this repo):** Discord is supported when `DISCORD_BOT_TOKEN` + `DISCORD_ALLOWED_USERS` are set in the local `.env`. `make push-config` forwards them to the VPS and restarts the gateway. Manual portal setup (§3) is still required first.

**Your intended mode:** private Discord server channels + DMs; **cron / home channel on Discord** (Telegram remains available for chat).

---

## 1. Is Discord possible?

**Yes.** Hermes treats Discord as a first-class messaging platform.

| Fact | Detail |
|------|--------|
| Same process | One `hermes gateway` (systemd user unit) can run **Telegram + Discord** (and more) at once |
| Transport | Discord **Gateway WebSocket** (outbound WSS to Discord). Not a simple webhook bot |
| Agent path | Message → allowlist → mention/channel rules → session → full agent (tools, memory, skills) → reply |
| Features | DMs, server channels, threads, slash commands, attachments, reactions, optional voice |
| This install | Upstream already ships `plugins/platforms/discord` and `hermes gateway setup` supports Discord |

Architecture (conceptual):

```
                    ┌─────────────────────────────────────┐
 Telegram ─────────►│                                     │
  (long poll)       │   hermes-gateway (one process)      │──► OpenRouter / tools / memory
 Discord  ─────────►│   adapters: telegram + discord      │──► ~/.hermes (shared profile)
  (WebSocket)       │                                     │
                    └─────────────────────────────────────┘
                              │
                    cron / notifications
                              │
                    home channel (you want Discord)
```

No second Hermes install is required. No inbound ports on the VPS for Discord (outbound only), same as Telegram long-polling.

---

## 2. How Hermes behaves on Discord

| Context | Default behavior |
|---------|------------------|
| **DMs** | Responds to every message from allowed users. Own session per DM. |
| **Server channels** | Responds only when **@mentioned** (`DISCORD_REQUIRE_MENTION=true`). |
| **Free-response channels** | Optional channel IDs where @mention is not required; replies **inline** (no auto-thread). |
| **Threads** | Replies in-thread; after the bot has joined, further messages usually need no mention (unless `thread_require_mention`). |
| **Auto-thread** | On @mention in a text channel, Hermes can create a thread so each conversation is isolated (`DISCORD_AUTO_THREAD=true` by default). |
| **Shared channels** | `group_sessions_per_user: true` (default): Alice and Bob get **separate** transcripts in the same channel. |
| **Other users @mentioned** | If the message mentions others but **not** the bot, Hermes stays silent (`DISCORD_IGNORE_NO_MENTION=true`). |
| **Other bots** | Ignored by default (`DISCORD_ALLOW_BOTS=none`). Do not enable bot-to-bot auto-reply loops. |

Full agent runs still apply: authorization, tools, Mnemosyne memory, skills, slash commands.

---

## 3. Manual setup (do this first)

Complete these steps **before** asking for deploy/Makefile changes. You need: a **private Discord server**, bot token, your user ID, and a home channel ID.

Order matters: **server first** → application/bot → intents/token → **invite link** → join bot to server → channels + IDs.

### 3.1 Create a private Discord server (required)

Hermes needs a **guild** (server) for topic channels, home/cron delivery, and @mentions. DMs alone are not enough for your intended setup (private channels + Discord as cron home).

You can reuse an existing private server you own, or create a new one dedicated to Hermes (recommended: keeps noise and permissions clean).

**Create a new server (Discord desktop or web app — not the Developer Portal):**

1. Open the [Discord app](https://discord.com/app) or desktop client (logged in as you).
2. In the **left server rail** (vertical list of server icons), click the **green `+`** (Add a Server).
3. Choose **Create My Own** (not “Join a Server”).
4. Choose **For me and my friends** (or equivalent “personal” template).
5. **Server name:** e.g. `Hermes` or `AI Lab`.
6. Optional: upload an icon → **Create**.
7. You are now **owner** of this server (full **Manage Server** rights — required to invite bots).

**Keep it private:**

- Do **not** enable Community / make it a big public server unless you know why.
- Default invite links: don’t post them publicly.
- Later you can invite only people you trust (or keep it solo).

**Optional cleanup after create:**

- Rename or delete the default `#general` if you want a clean slate.
- You’ll create `#hermes-home` and topic channels in §3.8.

You now have a server that will appear in the **“Add to Server”** dropdown when you open the bot invite URL.

### 3.2 Create a Discord application (Developer Portal)

This is a **different site** from the Discord chat app.

1. Open [Discord Developer Portal](https://discord.com/developers/applications) in a browser (same Discord login).
2. Top right → **New Application**.
3. Name e.g. `Hermes` → accept Developer Terms → **Create**.
4. You land on **General Information**.
5. Copy **Application ID** (also called Client ID) — you need it for the invite URL.  
   Keep this tab open or paste the ID into a notes file.

### 3.3 Create the bot user

Still in the Developer Portal, **same application**:

1. Left sidebar → **Bot**.
2. Discord usually already created a bot user. Set username/avatar if you want.
3. Scroll to **Authorization Flow** / bot settings (labels vary slightly by UI version):
   - **Public Bot:** **ON** is fine for a private server (only controls whether others can easily add the bot; you still only invite it to *your* server).  
     If you set Public Bot **OFF**, skip Installation UI and use **manual URL** or **OAuth2 URL Generator** in §3.6.
   - **Require OAuth2 Code Grant:** **OFF**.
4. Click **Save Changes** if the page shows a save button.

### 3.4 Enable Privileged Gateway Intents (critical)

Still on **Bot** page, scroll to **Privileged Gateway Intents**:

| Intent | Required? | Why |
|--------|-----------|-----|
| **Message Content Intent** | **Yes** | Without it the bot is “online” but message text is empty — it cannot read what you typed |
| **Server Members Intent** | **Yes** (for this setup) | Member/username resolution; role allowlists and some allowlist modes |
| **Presence Intent** | No | Online status; Hermes does not require it |

1. Toggle **Message Content Intent** → **ON**.
2. Toggle **Server Members Intent** → **ON**.
3. Click **Save Changes** at the bottom of the page.

**#1 failure mode:** bot online, never replies → Message Content Intent off or not saved.

**Scale note:** on a **personal / private server** you can toggle these freely. Extra Discord verification only matters at large scale. **Not a concern for one private server.**

### 3.5 Bot token

Still on **Bot** page:

1. Under **Token**, click **Reset Token** (or **View Token** if shown).
2. Confirm 2FA if Discord asks.
3. **Copy the token immediately** — it is often shown only once.
4. Store it in a password manager. Later this becomes `DISCORD_BOT_TOKEN` in `.env`.

Anyone with the token controls the bot. Never commit it to git or paste it into Telegram/Discord chats or screenshots.

### 3.6 Build the invite URL and permissions (explicit)

You are still in the **Developer Portal**, not the chat app. Goal: produce a browser URL that, when opened, invites **this bot** into **your private server** with the right scopes and permissions.

**What the link must include:**

| Piece | Value | Why |
|-------|--------|-----|
| `client_id` | Your **Application ID** from §3.2 | Which app/bot to install |
| `scope` | `bot` **and** `applications.commands` | Join as bot + register slash commands |
| `permissions` | Integer bitfield (recommended below) | What the bot may do in the server |

**Recommended permissions (check these if using a checkbox UI):**

- View Channels  
- Send Messages  
- Send Messages in Threads  
- Embed Links  
- Attach Files  
- Read Message History  
- Add Reactions  

| Level | Permission integer (for the URL) |
|-------|----------------------------------|
| Minimal | `117760` |
| **Recommended (use this)** | `274878286912` |

There is **no single “Edit invite” screen** on every account. Discord shows different UIs. Use **one** of the three methods below until you have a working invite link.

---

#### Method 1 — OAuth2 → URL Generator (most reliable; look here first)

This is the classic flow and usually the easiest to find.

1. Developer Portal → select your application.
2. Left sidebar → **OAuth2**.
3. Open **URL Generator**  
   (sometimes a sub-item under OAuth2, sometimes a tab on the OAuth2 page: **URL Generator**).
4. Under **Scopes**, check exactly:
   - [x] **`bot`**
   - [x] **`applications.commands`**
5. After you check `bot`, a **Bot Permissions** panel appears (below or beside scopes). Check the recommended permissions listed above  
   (or set the permission integer if the UI shows a numeric field — use `274878286912`).
6. Scroll to the bottom. Discord shows a generated URL, e.g.  
   `https://discord.com/api/oauth2/authorize?client_id=...&permissions=...&scope=bot+applications.commands`
7. Click **Copy** next to that URL.

You will **open this URL in the next section (§3.7)**. Do not skip copying it.

---

#### Method 2 — Installation tab (newer UI; only if you see it)

Some applications show an **Installation** item in the left sidebar (sibling of Bot / OAuth2). If you **do not** see it, use Method 1 or 3 — that is normal.

1. Left sidebar → **Installation**.
2. **Installation Contexts:** enable **Guild Install** (install into a server).  
   You can leave User Install off for this setup.
3. **Install Link:** choose **Discord Provided Link** (requires Public Bot ON from §3.3).
4. Under **Default Install Settings** → **Guild Install**:
   - **Scopes:** `bot` and `applications.commands`
   - **Permissions:** same checklist as above (or recommended integer)
5. Copy the **install / invite link** Discord shows on that page.

---

#### Method 3 — Manual URL (always works; no special page)

1. Copy **Application ID** from **General Information** (§3.2).
2. Paste into a text editor and build this exact pattern (one line):

```text
https://discord.com/oauth2/authorize?client_id=YOUR_APP_ID&scope=bot+applications.commands&permissions=274878286912
```

3. Replace `YOUR_APP_ID` with the real Application ID (digits only, no spaces).
4. Example shape (fake id):

```text
https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot+applications.commands&permissions=274878286912
```

5. Copy the finished URL.

If Public Bot is OFF, Method 3 or Method 1 still work; Method 2’s “Discord Provided Link” may not.

---

#### If you still cannot find any of the above

| You want | Where to click |
|----------|----------------|
| Application ID | Sidebar **General Information** → Application ID → Copy |
| Scopes + permissions UI | Sidebar **OAuth2** → **URL Generator** |
| Token / intents | Sidebar **Bot** (not OAuth2) |
| Chat server list | Discord **app** (discord.com/app), not Developer Portal |

### 3.7 Invite the bot into your private server

1. Paste the invite URL from §3.6 into a **browser** (Chrome/Safari/etc.), while logged into the **same** Discord account that owns the server.
2. Discord shows an authorize screen:
   - **Add to Server** (dropdown) → select the server from §3.1 (e.g. `Hermes`).
   - If the server is missing: you are on the wrong Discord account, or you are not allowed to manage that server.
3. Confirm the permission list looks right → **Continue** / **Authorize**.
4. Complete CAPTCHA if prompted.
5. Open the **Discord app** → your private server → **Member List** (right side, or Server Settings → Members).
6. You should see the **bot user** (bot badge). Status is **offline** until Hermes runs with `DISCORD_BOT_TOKEN` — that is expected at this stage.

**Channel visibility:** if the bot cannot see a channel later, edit the channel → Permissions → allow the bot role to View Channel + Send Messages (or put the bot’s role above restricted categories).

### 3.8 Create channels and collect IDs (Developer Mode)

Still in the **Discord app** on your private server:

**Recommended channels:**

| Channel | Purpose |
|---------|---------|
| `#hermes-home` | Cron / proactive notifications only (your **home**) |
| `#hermes` | Optional always-on chat (later: free-response) |
| Topic channels | e.g. `#job-hunt`, `#infra` — separate Hermes conversations |

**Create a channel:** server name (top left) → **Create Channel** → Text → name → Create.

**Enable Developer Mode (needed to copy IDs):**

1. User Settings (gear next to your avatar) → **Advanced** → **Developer Mode** → **ON**.
2. Close settings.

**Copy IDs:**

| ID | How | Used for |
|----|-----|----------|
| **Your User ID** | Right-click **your** avatar/name → **Copy User ID** | `DISCORD_ALLOWED_USERS` |
| **Home channel ID** | Right-click `#hermes-home` → **Copy Channel ID** | `DISCORD_HOME_CHANNEL` |
| Optional free-response channel | Right-click `#hermes` → **Copy Channel ID** | `DISCORD_FREE_RESPONSE_CHANNELS` |
| Optional server (guild) ID | Right-click server icon/name → **Copy Server ID** | docs / routing only |

Store these next to the bot token (password manager or private notes). You will paste them into `.env` during implementation.

### 3.9 Checklist before implementation

- [ ] **Private Discord server** created (or existing one you own)  
- [ ] Application + bot created in Developer Portal  
- [ ] Message Content + Server Members intents ON and **saved**  
- [ ] Bot token stored offline  
- [ ] Invite URL built (OAuth2 URL Generator / Installation / manual) with `bot` + `applications.commands` + recommended permissions  
- [ ] Bot **authorized into** that server (visible in member list, may be offline)  
- [ ] `#hermes-home` (and any topic channels) created  
- [ ] Your numeric **User ID** copied  
- [ ] **Home channel ID** copied  
- [ ] (Optional) free-response channel ID copied  
- [ ] Telegram still working (do not remove Telegram secrets yet)

When this list is done, implementation can add `DISCORD_*` to `.env.sample`, `deploy.sh` runtime filter, and config defaults.

---

## 4. What implementation will need later (not done yet)

### 4.1 Secrets (local `.env` → VPS `~/.hermes/.env`)

```bash
# Required
DISCORD_BOT_TOKEN=...
DISCORD_ALLOWED_USERS=YOUR_DISCORD_USER_ID

# Home / cron (your choice: Discord is home)
DISCORD_HOME_CHANNEL=CHANNEL_ID
DISCORD_HOME_CHANNEL_NAME="#hermes-home"

# Optional hardening / UX
# DISCORD_FREE_RESPONSE_CHANNELS=...
# DISCORD_ALLOWED_CHANNELS=...
# DISCORD_IGNORED_CHANNELS=...
# DISCORD_REQUIRE_MENTION=true
# DISCORD_AUTO_THREAD=true
```

**Never** set `DISCORD_ALLOW_ALL_USERS=true` or `GATEWAY_ALLOW_ALL_USERS=true` on this VPS (terminal tools enabled).

### 4.2 Config (`config.yaml`) — illustrative defaults

```yaml
# Global session isolation (all platforms)
group_sessions_per_user: true

discord:
  require_mention: true
  thread_require_mention: false
  auto_thread: true
  reactions: true
  # free_response_channels: ["..."]   # optional #hermes chat
  # ignored_channels: []
  # history_backfill: true
```

Env vars override config when both are set.

### 4.3 This repo’s deploy path

`scripts/deploy.sh` forwards `DISCORD_*` when **both** `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS` are set. `config/config.yaml.example` includes a `discord:` defaults block.

```bash
# After filling .env:
make push-config
```

Then:

1. Confirm bot shows **online** in the server  
2. Set/confirm home via env and/or Discord `/sethome` in `#hermes-home`  
3. Confirm cron delivery (jobs with `deliver: origin` follow the job’s origin; home is used for proactive/default delivery — verify after cutover)

### 4.4 Interactive alternative (on VPS)

```bash
hermes gateway setup   # select Discord, paste token + user id
hermes gateway restart
```

Prefer repo-managed `.env` + `make push-config` for repeatability.

---

## 5. Running Discord **in addition to** Telegram

### 5.1 What is shared vs separate

| Resource | Shared across platforms? |
|----------|---------------------------|
| Gateway process / systemd unit | Yes (one process) |
| Model, OpenRouter key, skills, Mnemosyne | Yes (same Hermes profile) |
| Cron job definitions | Yes (`~/.hermes/cron/jobs.json`) |
| Conversation sessions | **No** — separate session keys per platform/channel/user |
| Allowlists | **No** — `TELEGRAM_ALLOWED_USERS` vs `DISCORD_ALLOWED_USERS` |
| Home channel | **One primary home** for proactive delivery — you want **Discord** |

### 5.2 Consequences

1. **Chat continuity** — Telegram and Discord histories do **not** automatically merge. Same memory provider can still inject long-term facts; short-term thread context is per surface.
2. **Cron / notifications** — Moving home to Discord means job reports and proactive messages go to `DISCORD_HOME_CHANNEL` (or Discord `/sethome`). Telegram chat still works; it is no longer the default home.
3. **Cost** — Each platform turn burns OpenRouter tokens. Dual use ≈ more spend if you chat on both heavily.
4. **RAM / CPU** — Discord keeps a **persistent WebSocket** plus possible concurrent agent turns. This VPS is small (~1.6 GiB). Heavy Job Hunt + Discord + Telegram can OOM or thrash swap. Watch `free -h` and gateway memory after enable.
5. **Security surface** — Two tokens, two allowlists. Misconfiguring Discord open-access is as dangerous as on Telegram (Docker terminal, Notion, etc.).
6. **Ops** — One `hermes gateway restart` affects both. Discord reconnect / intent errors appear in the same `gateway.log`.
7. **UX differences** — Discord defaults to @mention + threads; Telegram DM is always-on chat. Train yourself (and any co-users) on mention rules.
8. **Slash commands** — Skills register as Discord application commands (cap applies; see §6). Telegram has a separate command menu limit.

### 5.3 Recommended policy for your setup

| Setting | Recommendation |
|---------|----------------|
| Allowlist | Only your Discord user ID |
| General channels | Keep `require_mention: true` |
| Optional `#hermes` | Free-response if you want chat without @ |
| `#hermes-home` | Home only; little human chatter |
| Telegram | Keep allowlist; keep as backup chat |
| Bots | Leave `DISCORD_ALLOW_BOTS=none` |
| Open-all flags | Never on this host |

### 5.4 After Discord is home (verification)

1. Bot shows **online** in the server.  
2. DM the bot → reply.  
3. @mention in a channel → reply (and thread if auto-thread on).  
4. `/sethome` in `#hermes-home` **or** env home set + restart.  
5. Trigger a test cron or wait for next run → output appears in Discord home.  
6. Confirm Telegram still answers DMs.  
7. Watch RAM during a long tool run.

---

## 6. Discord limitations and constraints

### 6.1 Do you need a paid plan?

| Product | Needed for Hermes bot? |
|---------|-------------------------|
| **Discord Nitro** (user sub) | **No** — personal cosmetic/upload perks for *your* user account, not required to run a bot |
| **Server Boost** | **No** for basic operation. Only raises **file upload** size for the *server* |
| **Discord paid “bot hosting”** | **N/A** — you host Hermes on your VPS; Discord does not charge for normal bot API use at personal scale |
| **Bot verification / intent review** | **No** for a private single-server bot |

**Bottom line:** for private server + DMs, **free Discord is enough**. Money you spend is VPS + OpenRouter, not Discord.

### 6.2 Hard platform limits (practical)

| Limit | Typical value | Impact on Hermes |
|-------|---------------|------------------|
| Message length | **~2000 characters** | Hermes **chunks** long replies |
| File upload (unboosted server) | **~25 MB** | Larger files may 413; Hermes may fall back to a path/link |
| Boosted upload | Up to much higher (tier-dependent) | Only if you boost the server |
| Global REST | ~**50 requests/s** per bot | Fine for personal use; bursts of many small messages can 429 |
| Gateway send | ~120 events / 60s / connection | Hermes should respect; spammy progress can hitch |
| Application slash commands | **100** global per app | Built-ins + skills share the pool; excess skills skipped with a log warning |
| Privileged intents at huge scale | Verification / review | Irrelevant for one private server |
| Identify storm | ~1000 IDENTIFY / 24h | Don’t restart the gateway in a tight loop |
| Invalid HTTP (401/403/429) | IP temp ban if extreme | Fix token/permissions; don’t hammer |

### 6.3 Product / UX constraints

- **Message Content Intent** is mandatory for normal chat bots.  
- **@mention culture** in servers vs always-on DMs.  
- **Auto-threads** can feel noisy; use free-response or `no_thread_channels` for a simple chat room.  
- **Forum channels** force thread posts (Hermes handles this).  
- **Bot-to-bot** conversations are unsupported and can ack-loop.  
- **Streaming** edit-style on Discord is optional and off by default in many configs (less “live typing” than some UIs).  
- **Voice** is optional and heavier (STT/TTS keys, CPU); not required for text + cron.

### 6.4 Security constraints (same class as Telegram)

- Token = full bot control → rotate if leaked.  
- Deny-by-default allowlist is mandatory with terminal tools.  
- Channel allow/deny lists reduce blast radius if the bot is in a server with other humans later.  
- Attachment downloads consume **VPS RAM/disk**; keep size caps unless you trust every uploader.

---

## 7. Troubleshooting (preview)

| Symptom | Likely cause |
|---------|----------------|
| Online, never replies | Message Content Intent off |
| `PrivilegedIntentsRequired` / close 4014 | Intent not enabled or not saved |
| Connects then ignores you | Not on `DISCORD_ALLOWED_USERS` |
| Replies in DM only | Channel needs @mention or free-response / allowed-channels mis-set |
| Cron still on Telegram | Home still Telegram; set Discord home + restart; check job `deliver` / origin |
| 413 on files | Over server upload limit (~25 MB unboosted) |
| OOM / gateway dies | Dual platform + heavy tools on small VPS |
| Slash commands missing/flapping | Multiple gateways same app; or >100 commands |

Logs on VPS:

```bash
hermes gateway status
journalctl --user -u hermes-gateway -f
# or
tail -f ~/.hermes/logs/gateway.log
```

---

## 8. Comparison snapshot: Telegram vs Discord (this stack)

| | Telegram (current) | Discord (current) |
|--|--------------------|-------------------|
| Transport | Long poll (default) | Persistent WebSocket |
| Inbound ports | None | None |
| Auth | `TELEGRAM_*` allowlist | `DISCORD_*` allowlist |
| Groups/channels | Privacy mode / mentions | @mention / free-response / threads |
| Home / cron | Telegram today | **Move to Discord** (your choice) |
| Paid platform fee | Free bot API | Free bot API at personal scale |
| Repo automation | Implemented | Implemented (`make push-config` when both DISCORD_* set) |

---

## 9. References

- Upstream: [Discord setup](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord)  
- Upstream: [Messaging gateway](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/)  
- Discord: [Developer Portal](https://discord.com/developers/applications)  
- Discord: [Rate limits](https://discord.com/developers/docs/topics/rate-limits)  
- Discord: [Gateway & privileged intents](https://discord.com/developers/docs/topics/gateway#privileged-intents)  
- This repo: [04-telegram-gateway](04-telegram-gateway.md) · [03-configuration](03-configuration.md) · [06-security](06-security.md)

---

## 10. Activate (after §3.9 checklist)

```bash
# Local machine: ensure .env has DISCORD_BOT_TOKEN + DISCORD_ALLOWED_USERS (+ home channel)
make push-config
```

### Simple tests

1. **Bot online** — Discord server member list shows the bot green/online (not grey).  
2. **DM** — Open a DM with the bot → send `ping` or `hello` → expect a reply.  
3. **Channel @mention** — In a text channel the bot can see: `@BotName hello` → reply (often in a thread if auto-thread is on).  
4. **Allowlist** — A non-allowlisted account should get no useful access.  
5. **Home** — In `#hermes-home` run `/sethome` (or rely on `DISCORD_HOME_CHANNEL`) → later cron/proactive should land there.  
6. **Logs (VPS)** — `journalctl --user -u hermes-gateway -f` or `tail -f ~/.hermes/logs/gateway.log` and look for `discord connected` / similar.  
7. **Telegram still works** — send a DM there; both platforms share one gateway.

If online but silent: Message Content Intent (§3.4). If ignored: wrong `DISCORD_ALLOWED_USERS` or channel permissions.
