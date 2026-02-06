# openclaw-opus46-installer

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/txc0ld/openclaw-opus46-installer/ci.yml?label=CI)](https://github.com/txc0ld/openclaw-opus46-installer/actions)
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)]()

**Add Claude Opus 4.6 to [OpenClaw](https://openclaw.ai) in one command.**

> [!CAUTION]
> **Unofficial community tool.** Not affiliated with Anthropic or OpenClaw. Setups vary across versions and platforms. Always preview changes with `--dry-run` before applying.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What It Does](#what-it-does)
- [What It Does Not Touch](#what-it-does-not-touch)
- [How the Config Merge Works](#how-the-config-merge-works)
- [Options Reference](#options-reference)
- [Post-Installation](#post-installation)
- [Requirements](#requirements)
- [Platform Compatibility](#platform-compatibility)
- [Troubleshooting](#troubleshooting)
- [Manual Installation](#manual-installation)

---

## Quick Start

**Option A — Clone and run (recommended):**

```bash
git clone https://github.com/txc0ld/openclaw-opus46-installer.git
cd openclaw-opus46-installer
chmod +x install-opus46.sh
```

```bash
./install-opus46.sh --dry-run   # Preview — no files written
./install-opus46.sh             # Apply
```

**Option B — One-line install:**

```bash
curl -fsSL https://raw.githubusercontent.com/txc0ld/openclaw-opus46-installer/main/install-opus46.sh -o install-opus46.sh
less install-opus46.sh          # Review the script first
bash install-opus46.sh
```

> [!WARNING]
> Piping `curl` directly to `bash` executes arbitrary code sight-unseen. The command above downloads to a file first so you can inspect it. If you pipe directly, `--force` is automatically rejected as a safety measure.

---

## What It Does

The installer modifies **exactly two files**. Both are backed up with a timestamped suffix before any write.

| File | Change |
|------|--------|
| `models.generated.js` | Inserts a `claude-opus-4-6` catalog entry above each `claude-opus-4-5` block, inheriting its `provider` field. |
| `openclaw.json` | Adds `anthropic/claude-opus-4-6` to the model allowlist with alias `opus46`. If per-agent allowlists exist in `agents.list[]`, adds it there too. |

By default, the installer **asks whether to set Opus 4.6 as the primary model** (default: yes). Pass `--no-primary` to skip the prompt and keep your current default.

---

## What It Does Not Touch

The installer does not read, write, or interact with anything outside the two files listed above. The following remain completely untouched:

| Category | Protected Assets |
|----------|-----------------|
| **Identity** | `SOUL.md` · `IDENTITY.md` · `AGENTS.md` · `USER.md` · `MEMORY.md` |
| **Skills** | `TOOLS.md` · `skills/` directories · ClawHub installs · bundled skills |
| **Workspaces** | All workspace directories, files, and subdirectories |
| **Agent State** | `agents/*/` · sessions · transcripts |
| **Credentials** | `auth-profiles.json` · `auth.json` · OAuth tokens |
| **Infrastructure** | Channels · hooks · cron jobs · plugins · sandbox config |
| **Config Structure** | Every existing key, value, and nesting order in `openclaw.json` |

---

## How the Config Merge Works

The configuration patch uses a **deep-merge strategy**: it traverses the existing JSON tree and inserts only the keys that do not already exist. No existing key is overwritten, removed, or reordered.

**Before:**

```json
{
  "agents": {
    "defaults": {
      "model": { "primary": "anthropic/claude-opus-4-5" },
      "models": {
        "anthropic/claude-opus-4-5": { "alias": "opus" },
        "anthropic/claude-sonnet-4-5": { "alias": "sonnet" }
      },
      "workspace": "/home/you/.openclaw/workspace"
    },
    "list": [
      { "id": "main", "identity": { "name": "MyBot", "emoji": "🦞" } }
    ]
  },
  "skills": { "load": { "watch": true } },
  "channels": { "telegram": { "enabled": true } }
}
```

**After:**

```diff
  "models": {
    "anthropic/claude-opus-4-5": { "alias": "opus" },
    "anthropic/claude-sonnet-4-5": { "alias": "sonnet" },
+   "anthropic/claude-opus-4-6": { "alias": "opus46" }
  },
```

One key inserted. Everything else — `primary`, `workspace`, `list`, `identity`, `skills`, `channels` — is identical. During installation, you'll be asked whether to also set `agents.defaults.model.primary` to Opus 4.6 (pass `--no-primary` to skip).

---

## Options Reference

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview all changes as a unified diff. No files are written. |
| `--add-only` | Patch the model catalog only. Skip `openclaw.json` entirely. |
| `--no-primary` | Skip the primary model prompt. Keep current primary unchanged. |
| `--rollback` | Restore the most recent timestamped backup for both files. |
| `--no-restart` | Apply patches without restarting the gateway. |
| `--force` | Bypass compatibility checks and confirmation prompts. Rejected when stdin is piped. |
| `--help` | Print usage information and exit. |

### Default Behavior (No Flags)

1. Adds `claude-opus-4-6` to the model catalog.
2. Registers `anthropic/claude-opus-4-6` in the config allowlist (alias: `opus46`).
3. Asks whether to set it as the primary model (default: yes).
4. Adds the entry to any per-agent `models` allowlists found in `agents.list[]`.
5. Cold-restarts the gateway (required for catalog changes to take effect).

Pass `--no-primary` to skip the prompt and keep your current primary model.

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `CATALOG_FILE` | Override auto-detected path to `models.generated.js` |
| `CONFIG_FILE` | Override auto-detected path to `openclaw.json` |

---

## Post-Installation

Opus 4.6 is now the primary model. Verify it's active:

```
/model status
```

Switch back to your previous model at any time:

```
/model opus
```

If you installed with `--no-primary`, switch to Opus 4.6 manually:

```
/model opus46
```

> **Note:** Running `npm update -g openclaw` will overwrite `models.generated.js` and remove the catalog entry. Re-run the installer after any OpenClaw update.

---

## Requirements

| Dependency | Minimum Version | Notes |
|------------|----------------|-------|
| Node.js | 22 | Required by OpenClaw |
| Python | 3.6 | JSON deep-merge and catalog patching. Pre-installed on macOS and most Linux. |
| OpenClaw | Any with `claude-opus-4-5` in catalog | Supports `openclaw`, `moltbot`, and `clawdbot` CLI variants |
| Anthropic API key | — | Must be configured in OpenClaw before installation |

---

## Platform Compatibility

| Platform | Auto-Detected Path | Status |
|----------|--------------------|--------|
| macOS (Apple Silicon) | `/opt/homebrew/lib/node_modules/` | ✅ |
| macOS (Intel) | `/usr/local/lib/node_modules/` | ✅ |
| Linux | `/usr/lib/node_modules/` | ✅ |
| npm global | `$(npm root -g)/` | ✅ |
| pnpm global | `$(pnpm root -g)/` | ✅ |
| Windows (WSL2) | Linux paths via WSL | ✅ |
| Docker / Zeabur | Container paths | ⚙ Use `CATALOG_FILE` |

Non-standard locations:

```bash
CATALOG_FILE=/path/to/models.generated.js CONFIG_FILE=/path/to/openclaw.json ./install-opus46.sh
```

---

## Troubleshooting

### Could not find `models.generated.js`

Locate the file manually, then pass it in:

```bash
find / -name "models.generated.js" -path "*pi-ai*" 2>/dev/null
CATALOG_FILE=/path/to/result ./install-opus46.sh
```

### Gateway failed to start

Diagnose or revert:

```bash
openclaw gateway --verbose        # surface the error
./install-opus46.sh --rollback    # restore pre-patch state
```

### Model not allowed

If your agents define per-agent `models` allowlists, the installer adds the entry automatically. If you use additional filtering (provider-level restrictions, plugin gates), add `anthropic/claude-opus-4-6` to the relevant allowlist manually.

### Config corruption

```bash
./install-opus46.sh --rollback    # restore from timestamped backup
openclaw doctor --fix             # OpenClaw native repair
```

---

## Manual Installation

Step-by-step instructions without the automated script: **[MANUAL.md](MANUAL.md)**

---

## License

[MIT](LICENSE)

---

<sub>Unofficial community tool. Not endorsed by, affiliated with, or supported by Anthropic or OpenClaw. Provided as-is with no warranty. Review all changes with `--dry-run` and maintain backups.</sub>
