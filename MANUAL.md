# Manual Installation Guide

> [!CAUTION]
> **Unofficial community patch.** Not affiliated with Anthropic or OpenClaw. Configurations vary across versions and platforms. Read this guide fully before making any changes.

This document reproduces the exact changes made by `install-opus46.sh`, presented as discrete manual steps.

---

## Prerequisites

Confirm the following before proceeding:

| Requirement | Verification |
|-------------|-------------|
| OpenClaw installed | `openclaw gateway status` returns a valid response |
| `claude-opus-4-5` in catalog | `grep "claude-opus-4-5" /path/to/models.generated.js` returns matches |
| Anthropic API key configured | Configured via `openclaw auth` or present in `auth-profiles.json` |

---

## Change Surface

This procedure modifies **exactly two files**:

| File | Change |
|------|--------|
| `models.generated.js` | Adds `claude-opus-4-6` to the internal model catalog |
| `openclaw.json` | Registers the model in the configuration allowlist |

**Nothing else is modified.** Identity files (`SOUL.md`, `IDENTITY.md`, `AGENTS.md`, `TOOLS.md`, `USER.md`, `MEMORY.md`), skill directories, workspaces, agent state, credentials, channels, hooks, plugins, and all other configuration keys are left untouched.

---

## Step 1 — Locate the Model Catalog

The catalog file resides inside the globally installed OpenClaw package. Its path varies by platform and package manager.

**macOS (Apple Silicon — Homebrew):**

```bash
find /opt/homebrew/lib/node_modules/openclaw -name "models.generated.js" -path "*pi-ai*"
```

**macOS (Intel — Homebrew):**

```bash
find /usr/local/lib/node_modules/openclaw -name "models.generated.js" -path "*pi-ai*"
```

**Linux (system global):**

```bash
find /usr/lib/node_modules/openclaw -name "models.generated.js" -path "*pi-ai*"
```

**npm / pnpm global (any platform):**

```bash
find "$(npm root -g)" -name "models.generated.js" -path "*pi-ai*" 2>/dev/null
find "$(pnpm root -g)" -name "models.generated.js" -path "*pi-ai*" 2>/dev/null
```

> If installed under a previous project name, substitute `openclaw` with `clawdbot` or `moltbot`.

Record the full path — referred to as `<CATALOG>` in subsequent steps.

---

## Step 2 — Create Backups

```bash
cp <CATALOG> <CATALOG>.bak
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak
```

> Adjust the config path for `~/.moltbot/moltbot.json` or `~/.clawdbot/clawdbot.json` if applicable.

---

## Step 3 — Patch the Model Catalog

Open `<CATALOG>` in a text editor. Search for `"claude-opus-4-5"`. You will typically find **two entries** — one with `provider: "anthropic"` and one with `provider: "opencode"`.

Insert the following block **directly above each** `claude-opus-4-5` entry. Set the `provider` field to match the entry immediately below it:

```javascript
"claude-opus-4-6": {
    id: "claude-opus-4-6",
    name: "Claude Opus 4.6 (latest)",
    api: "anthropic-messages",
    provider: "anthropic",        // ← match the claude-opus-4-5 entry below
    baseUrl: "https://api.anthropic.com",
    reasoning: true,
    input: ["text", "image"],
    cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
    contextWindow: 200000,
    maxTokens: 64000,
},
```

Repeat for each `claude-opus-4-5` block, adjusting `provider` accordingly.

---

## Step 4 — Register the Model in Configuration

Open `~/.openclaw/openclaw.json`.

**If `agents.defaults.models` exists**, add one entry:

```json
"anthropic/claude-opus-4-6": { "alias": "opus46" }
```

**If no `models` section exists**, create it under `agents.defaults`:

```json
"models": {
  "anthropic/claude-opus-4-6": { "alias": "opus46" }
}
```

> [!IMPORTANT]
> **Do not modify `primary`** unless you explicitly intend to change your default model. Switch interactively at any time with `/model opus46`.
>
> **Do not alter any other keys.** Identity, skills, channels, workspace paths, agent definitions — all must remain as-is. This is an additive change only.

---

## Step 5 — Per-Agent Allowlists

If any agents in `agents.list[]` define their own `models` allowlist, the new model must be added there as well. Otherwise the agent will reject it with `Model "anthropic/claude-opus-4-6" is not allowed`.

Add to each relevant agent:

```json
"anthropic/claude-opus-4-6": { "alias": "opus46" }
```

Example:

```json
{
  "id": "main",
  "models": {
    "anthropic/claude-opus-4-5": { "alias": "opus" },
    "anthropic/claude-sonnet-4-5": { "alias": "sonnet" },
    "anthropic/claude-opus-4-6": { "alias": "opus46" }
  }
}
```

Skip this step if your agents do not define per-agent `models` keys.

---

## Step 6 — Cold Restart the Gateway

> [!IMPORTANT]
> The gateway's config hot-reload does **not** detect changes to the model catalog. A full cold restart is required.

```bash
openclaw gateway stop && openclaw gateway start
```

> Use `moltbot` or `clawdbot` if running an older CLI variant.

---

## Step 7 — Verify

```
/model status                         # confirm opus46 appears
/model opus46                         # switch to Opus 4.6
/model anthropic/claude-opus-4-6      # alternative: full reference
```

---

## After `npm update`

Running `npm update -g openclaw` overwrites `models.generated.js`, removing the catalog entry. The config entry in `openclaw.json` is unaffected. Re-run **Step 3** (or the automated installer) after any OpenClaw package update.

---

## Rollback

Restore both backups and restart:

```bash
cp <CATALOG>.bak <CATALOG>
cp ~/.openclaw/openclaw.json.bak ~/.openclaw/openclaw.json
openclaw gateway stop && openclaw gateway start
```

Or use OpenClaw's built-in repair:

```bash
openclaw doctor --fix
```
