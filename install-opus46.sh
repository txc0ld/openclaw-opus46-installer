#!/usr/bin/env bash
# ============================================================================
# install-opus46.sh — Add Claude Opus 4.6 to OpenClaw / ClawdBot
# ============================================================================
#
# ⚠ UNOFFICIAL COMMUNITY TOOL — NOT AFFILIATED WITH ANTHROPIC OR OPENCLAW ⚠
#
# Surgical, additive patch. Modifies exactly two files:
#
#   1. models.generated.js  — inserts a claude-opus-4-6 catalog entry
#   2. openclaw.json         — registers the model in the config allowlist
#
# Does NOT touch:
#   • SOUL.md, IDENTITY.md, AGENTS.md, TOOLS.md, USER.md, MEMORY.md
#   • skills/ directories (bundled, managed, workspace, or ClawHub)
#   • Workspace files, sessions, or agent state
#   • Auth profiles, credentials, or OAuth tokens
#   • Channels, hooks, cron jobs, plugins, or sandbox config
#   • Any existing key in openclaw.json — only new keys are inserted
#
# Note: `npm update -g openclaw` will overwrite the catalog. Re-run this
# script after any OpenClaw package update.
#
# Run --dry-run first to preview the exact diff.
#
# Options:
#   --dry-run          Preview changes as a unified diff (no files written)
#   --add-only         Patch catalog only — skip openclaw.json
#   --set-primary      Also set Opus 4.6 as the primary model
#   --rollback         Restore the most recent timestamped backup
#   --no-restart       Apply patches without restarting the gateway
#   --force            Bypass compatibility checks and prompts (rejected when piped)
#   --help             Print usage information and exit
# ============================================================================

set -euo pipefail

# ── Output helpers ───────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERR]${NC}  $*"; }
fatal()   { err "$*"; exit 1; }

banner() {
  echo -e "${CYAN}${BOLD}"
  cat << 'BANNER'
   ____                    ____ _                 
  / __ \____  __  _______/ __ \ |____ __      __
 / / / / __ \/ / / / ___/ /  \/ / __ `/ | /| / /
/ /_/ / /_/ / /_/ (__  ) /___/ / /_/ /| |/ |/ / 
\____/ .___/\__,_/____/\____/_/\__,_/ |__/|__/  
    /_/                                          
  Opus 4.6 Installer for OpenClaw / ClawdBot  🦞
BANNER
  echo -e "${NC}"
  echo -e "${YELLOW}${BOLD}  ⚠  UNOFFICIAL — NOT AFFILIATED WITH ANTHROPIC OR OPENCLAW${NC}"
  echo -e "${DIM}  Community patch. Setups vary. Use --dry-run to preview changes.${NC}"
  echo ""
}

# ── Defaults ─────────────────────────────────────────────────────────────────

DRY_RUN=false
ADD_ONLY=false
SET_PRIMARY=false
ROLLBACK=false
NO_RESTART=false
FORCE=false
BACKUP_TS="$(date +%Y%m%d%H%M%S)"
BACKUP_SUFFIX=".opus46-backup-${BACKUP_TS}"
CATALOG_FILE="${CATALOG_FILE:-}"
CONFIG_FILE="${CONFIG_FILE:-}"
CLI_CMD=""

# ── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=true;      shift ;;
    --add-only)     ADD_ONLY=true;     shift ;;
    --set-primary)  SET_PRIMARY=true;  shift ;;
    --rollback)     ROLLBACK=true;     shift ;;
    --no-restart)   NO_RESTART=true;   shift ;;
    --force)        FORCE=true;        shift ;;
    --help|-h)
      banner
      echo "Usage: install-opus46.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dry-run          Preview all changes as a unified diff (no files written)"
      echo "  --add-only         Patch model catalog only; skip openclaw.json"
      echo "  --set-primary      Also set Opus 4.6 as the primary model"
      echo "  --rollback         Restore the most recent timestamped backup"
      echo "  --no-restart       Apply patches without restarting the gateway"
      echo "  --force            Bypass compatibility checks and prompts (rejected when piped)"
      echo "  --help             Display this message"
      echo ""
      echo "Default behavior:"
      echo "  1. Adds claude-opus-4-6 to the model catalog"
      echo "  2. Registers it in the config allowlist (alias: opus46)"
      echo "  3. Adds it to per-agent allowlists in agents.list[] (if present)"
      echo "  4. Cold-restarts the gateway"
      echo ""
      echo "  Does NOT change the primary model (use --set-primary)."
      echo "  Does NOT modify identity files, skills, workspaces, channels, or auth."
      echo ""
      echo "Environment:"
      echo "  CATALOG_FILE       Override catalog path (models.generated.js)"
      echo "  CONFIG_FILE        Override config path (openclaw.json)"
      exit 0
      ;;
    *)
      fatal "Unknown option: $1 (use --help for usage)"
      ;;
  esac
done

# ── Safety: reject --force when piped (e.g. curl | bash --force) ────────────
if [[ "$FORCE" == true ]] && ! [ -t 0 ]; then
  fatal "--force is not allowed when stdin is piped (e.g. curl | bash).\n       Clone the repo and run interactively to use --force."
fi

# ── Detect CLI command ───────────────────────────────────────────────────────

detect_cli() {
  if command -v openclaw &>/dev/null; then
    CLI_CMD="openclaw"
  elif command -v moltbot &>/dev/null; then
    CLI_CMD="moltbot"
  elif command -v clawdbot &>/dev/null; then
    CLI_CMD="clawdbot"
  else
    fatal "Could not find openclaw, moltbot, or clawdbot in PATH.\n       Is OpenClaw installed? See: https://docs.openclaw.ai/start/getting-started"
  fi
  success "CLI command: ${BOLD}${CLI_CMD}${NC}"
}

# ── Detect model catalog file ────────────────────────────────────────────────

detect_catalog() {
  if [[ -n "$CATALOG_FILE" && -f "$CATALOG_FILE" ]]; then
    success "Catalog (from env): ${BOLD}${CATALOG_FILE}${NC}"
    return 0
  fi

  local search_roots=()

  # Homebrew Apple Silicon
  [[ -d "/opt/homebrew/lib/node_modules" ]] && search_roots+=("/opt/homebrew/lib/node_modules")
  # Homebrew Intel
  [[ -d "/usr/local/lib/node_modules" ]] && search_roots+=("/usr/local/lib/node_modules")
  # Linux system
  [[ -d "/usr/lib/node_modules" ]] && search_roots+=("/usr/lib/node_modules")
  # npm global
  local npm_g; npm_g="$(npm root -g 2>/dev/null || true)"
  [[ -n "$npm_g" && -d "$npm_g" ]] && search_roots+=("$npm_g")
  # pnpm global
  local pnpm_g; pnpm_g="$(pnpm root -g 2>/dev/null || true)"
  [[ -n "$pnpm_g" && -d "$pnpm_g" ]] && search_roots+=("$pnpm_g")

  for pkg in openclaw moltbot clawdbot; do
    for root in "${search_roots[@]}"; do
      [[ -d "${root}/${pkg}" ]] || continue
      local found
      found=$(find "${root}/${pkg}" -name "models.generated.js" -path "*pi-ai*" 2>/dev/null | head -1)
      if [[ -n "$found" ]]; then
        CATALOG_FILE="$found"
        success "Catalog found: ${BOLD}${CATALOG_FILE}${NC}"
        return 0
      fi
    done
  done

  fatal "Could not find models.generated.js.\n       Set CATALOG_FILE=/path/to/models.generated.js and re-run.\n       Hint: find / -name 'models.generated.js' -path '*pi-ai*' 2>/dev/null"
}

# ── Detect config file ───────────────────────────────────────────────────────

detect_config() {
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    success "Config (from env): ${BOLD}${CONFIG_FILE}${NC}"
    return 0
  fi

  # Check standard config locations (OpenClaw, MoltBot, ClawdBot)
  local candidates=(
    "${HOME}/.openclaw/openclaw.json"
    "${HOME}/.moltbot/moltbot.json"
    "${HOME}/.clawdbot/clawdbot.json"
  )
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      CONFIG_FILE="$f"
      success "Config found: ${BOLD}${CONFIG_FILE}${NC}"
      return 0
    fi
  done

  # Default to the path matching the detected CLI
  case "$CLI_CMD" in
    openclaw)  CONFIG_FILE="${HOME}/.openclaw/openclaw.json" ;;
    moltbot)   CONFIG_FILE="${HOME}/.moltbot/moltbot.json" ;;
    clawdbot)  CONFIG_FILE="${HOME}/.clawdbot/clawdbot.json" ;;
  esac
  warn "No config file found. Will create: ${CONFIG_FILE}"
}

# ── Display protected files (read-only scan) ────────────────────────────────

show_protected_files() {
  local config_dir
  config_dir="$(dirname "$CONFIG_FILE")"

  echo -e "${DIM}  ┌─ Protected files (read-only — no modifications) ──────────┐${NC}"

  local found_any=false
  for pattern in \
    "${config_dir}/*.md" \
    "${config_dir}/workspace" \
    "${config_dir}/skills" \
    "${config_dir}/agents" \
    "${config_dir}/credentials" \
    "${config_dir}/agents/*/workspace/*.md" \
    "${config_dir}/agents/*/workspace/skills"; do
    local matches
    matches=$(compgen -G "$pattern" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      found_any=true
      while IFS= read -r f; do
        local rel="${f#"$config_dir"/}"
        echo -e "${DIM}  │  ✓ ${rel}${NC}"
      done <<< "$matches"
    fi
  done

  if [[ "$found_any" == false ]]; then
    echo -e "${DIM}  │  (no identity/workspace files detected in ${config_dir})${NC}"
  fi
  echo -e "${DIM}  └────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# ── Compatibility checks ────────────────────────────────────────────────────

check_compat() {
  if [[ "$FORCE" == true ]]; then
    warn "Skipping compatibility checks (--force)"
    return 0
  fi

  # Node version
  local node_ver
  node_ver="$(node --version 2>/dev/null || true)"
  if [[ -z "$node_ver" ]]; then
    fatal "Node.js not found. OpenClaw requires Node 22+."
  fi
  local major="${node_ver#v}"; major="${major%%.*}"
  if (( major < 22 )); then
    fatal "Node.js ${node_ver} detected — OpenClaw requires 22+."
  fi
  success "Node.js ${node_ver}"

  # Verify Opus 4.5 exists (our anchor point)
  if ! grep -q '"claude-opus-4-5"' "$CATALOG_FILE" 2>/dev/null; then
    fatal "claude-opus-4-5 not found in catalog. Your version may be too old.\n       Update first: npm update -g ${CLI_CMD}"
  fi
  success "claude-opus-4-5 found in catalog (anchor)"

  # Check if already patched
  if grep -q '"claude-opus-4-6"' "$CATALOG_FILE" 2>/dev/null; then
    warn "claude-opus-4-6 already exists in the catalog."
    if [[ "$FORCE" != true ]]; then
      read -rp "       Re-patch anyway? [y/N] " yn
      [[ "$yn" == [yY]* ]] || { info "Aborted. No changes made."; exit 0; }
    fi
  fi
}

# ── Backup (one file at a time) ─────────────────────────────────────────────

backup_file() {
  local src="$1"
  [[ -f "$src" ]] || return 0

  local dst="${src}${BACKUP_SUFFIX}"
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] Would backup: ${src}"
  else
    cp "$src" "$dst"
    success "Backed up: ${src} → ${dst##*/}"
  fi
}

# ── Rollback ─────────────────────────────────────────────────────────────────

do_rollback() {
  detect_cli
  info "Scanning for backups..."

  local restored=0

  # Catalog backups — search the same roots as detect_catalog(), not all of /
  local search_roots=()
  [[ -d "/opt/homebrew/lib/node_modules" ]] && search_roots+=("/opt/homebrew/lib/node_modules")
  [[ -d "/usr/local/lib/node_modules" ]]    && search_roots+=("/usr/local/lib/node_modules")
  [[ -d "/usr/lib/node_modules" ]]          && search_roots+=("/usr/lib/node_modules")
  local npm_g; npm_g="$(npm root -g 2>/dev/null || true)"
  [[ -n "$npm_g" && -d "$npm_g" ]] && search_roots+=("$npm_g")
  local pnpm_g; pnpm_g="$(pnpm root -g 2>/dev/null || true)"
  [[ -n "$pnpm_g" && -d "$pnpm_g" ]] && search_roots+=("$pnpm_g")

  # Also check CATALOG_FILE's directory if set via env
  if [[ -n "${CATALOG_FILE:-}" && -d "$(dirname "$CATALOG_FILE")" ]]; then
    search_roots+=("$(dirname "$CATALOG_FILE")")
  fi

  local catalog_backups=""
  for root in "${search_roots[@]}"; do
    local found
    found=$(find "$root" -name "models.generated.js.opus46-backup-*" 2>/dev/null || true)
    [[ -n "$found" ]] && catalog_backups="${catalog_backups}${found}"$'\n'
  done
  catalog_backups=$(echo "$catalog_backups" | grep -v '^$' | sort -r | head -5)

  if [[ -n "$catalog_backups" ]]; then
    local latest; latest=$(echo "$catalog_backups" | head -1)
    local orig="${latest%.opus46-backup-*}"
    echo ""
    info "Found catalog backup: ${latest}"
    info "  → Restore to: ${orig}"
    read -rp "       Restore this? [Y/n] " yn
    if [[ "$yn" != [nN]* ]]; then
      cp "$latest" "$orig"
      success "Catalog restored"
      ((restored++))
    fi
  fi

  # Config backups
  for cfg_dir in "${HOME}/.openclaw" "${HOME}/.moltbot" "${HOME}/.clawdbot"; do
    local backups
    backups=$(ls -t "${cfg_dir}"/*.json.opus46-backup-* 2>/dev/null | head -1 || true)
    if [[ -n "$backups" ]]; then
      local orig="${backups%.opus46-backup-*}"
      echo ""
      info "Found config backup: ${backups}"
      info "  → Restore to: ${orig}"
      read -rp "       Restore this? [Y/n] " yn
      if [[ "$yn" != [nN]* ]]; then
        cp "$backups" "$orig"
        success "Config restored"
        ((restored++))
      fi
    fi
  done

  if (( restored == 0 )); then
    fatal "No backups found."
  fi

  echo ""
  warn "Restart the gateway to apply restored files:"
  echo -e "  ${BOLD}${CLI_CMD} gateway stop && ${CLI_CMD} gateway start${NC}"
  exit 0
}

# ── Generate patched catalog ─────────────────────────────────────────────────

generate_patched_catalog() {
  local src="$1"
  local dst="$2"

  python3 -c "
import re, sys, shutil

src = '$src'
dst = '$dst'

with open(src, 'r') as f:
    content = f.read()

# First, strip any existing opus-4-6 entries (idempotent re-run)
content = re.sub(r'\"claude-opus-4-6\":\s*\{[^}]*\},?\s*', '', content)

# Find each claude-opus-4-5 block and extract its provider
pattern = r'(\"claude-opus-4-5\":\s*\{[^}]*?provider:\s*\"([^\"]+)\")'
matches = list(re.finditer(pattern, content))

if not matches:
    print('FATAL: No claude-opus-4-5 entries found in catalog.', file=sys.stderr)
    sys.exit(1)

# Insert in reverse order so character positions stay valid
for match in reversed(matches):
    provider = match.group(2)
    block = (
        '\"claude-opus-4-6\": {{\n'
        '    id: \"claude-opus-4-6\",\n'
        '    name: \"Claude Opus 4.6 (latest)\",\n'
        '    api: \"anthropic-messages\",\n'
        '    provider: \"{provider}\",\n'
        '    baseUrl: \"https://api.anthropic.com\",\n'
        '    reasoning: true,\n'
        '    input: [\"text\", \"image\"],\n'
        '    cost: {{ input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 }},\n'
        '    contextWindow: 200000,\n'
        '    maxTokens: 64000,\n'
        '  }},\n'
        '  '
    ).format(provider=provider)
    content = content[:match.start()] + block + content[match.start():]

with open(dst, 'w') as f:
    f.write(content)

providers = [m.group(2) for m in matches]
print(f'Added {len(matches)} Opus 4.6 entries (providers: {chr(44).join(providers)})')
" 2>&1
}

# ── Generate patched config via deep merge ───────────────────────────────────
#
# Deep-merge strategy:
#   • Traverses existing JSON tree — only inserts keys that do not exist
#   • Adds agents.defaults.models."anthropic/claude-opus-4-6"
#   • Adds to any agents.list[].models allowlists that already exist
#   • Optionally sets agents.defaults.model.primary (--set-primary)
#   • Never overwrites, removes, renames, or restructures any existing key
#   • Identity, skills, channels, workspaces — all preserved

generate_patched_config() {
  local src="$1"
  local dst="$2"
  local set_primary="$3"  # "true" or "false"

  python3 -c "
import json, sys, copy, os

src = '$src'
dst = '$dst'
set_primary = ('$set_primary' == 'true')

# ── Load existing config or start minimal ────────────────────────────
if os.path.isfile(src) and os.path.getsize(src) > 0:
    with open(src, 'r') as f:
        raw = f.read().strip()
        if not raw:
            config = {}
        else:
            try:
                config = json.loads(raw)
            except json.JSONDecodeError as e:
                print(f'FATAL: Config is not valid JSON: {e}', file=sys.stderr)
                sys.exit(1)
else:
    config = {}

# Keep a deep copy of the original for diffing
original = json.dumps(config, indent=2, sort_keys=True)

# ── Deep-merge helper ────────────────────────────────────────────────
# Only sets keys that don't exist. Never overwrites existing values.
def deep_set(obj, keys, value, overwrite=False):
    for key in keys[:-1]:
        if key not in obj or not isinstance(obj[key], dict):
            obj[key] = {}
        obj = obj[key]
    final_key = keys[-1]
    if overwrite or final_key not in obj:
        obj[final_key] = value
        return True
    return False

# ── Add opus-4-6 to the model allowlist ──────────────────────────────
# Path: agents.defaults.models.\"anthropic/claude-opus-4-6\"
# This adds it alongside existing models — does NOT remove any.
deep_set(config, ['agents', 'defaults', 'models', 'anthropic/claude-opus-4-6'], {'alias': 'opus46'})

# ── Optionally set as primary ────────────────────────────────────────
if set_primary:
    deep_set(config, ['agents', 'defaults', 'model', 'primary'], 'anthropic/claude-opus-4-6', overwrite=True)

# ── Also add to agents.list[] entries if they have model allowlists ──
# Some users define per-agent model restrictions. Add opus-4-6 there too
# so it doesn't get rejected as 'Model not allowed'.
agents_list = config.get('agents', {}).get('list', [])
for agent in agents_list:
    if isinstance(agent, dict):
        # If the agent has a 'models' allowlist, add opus-4-6 to it
        agent_models = agent.get('models', None)
        if isinstance(agent_models, dict) and 'anthropic/claude-opus-4-6' not in agent_models:
            agent_models['anthropic/claude-opus-4-6'] = {'alias': 'opus46'}

# ── Write patched config ─────────────────────────────────────────────
patched = json.dumps(config, indent=2, sort_keys=True)

with open(dst, 'w') as f:
    # Preserve original key order (not sorted) for the actual file
    json.dump(config, f, indent=2)
    f.write('\n')

# ── Report what changed ──────────────────────────────────────────────
if original == patched:
    print('No config changes needed (opus-4-6 already present)')
else:
    changes = []
    changes.append('+ agents.defaults.models.\"anthropic/claude-opus-4-6\" = {alias: \"opus46\"}')
    if set_primary:
        changes.append('~ agents.defaults.model.primary = \"anthropic/claude-opus-4-6\"')
    for agent in agents_list:
        if isinstance(agent, dict) and 'id' in agent:
            agent_models = agent.get('models', {})
            if isinstance(agent_models, dict) and 'anthropic/claude-opus-4-6' in agent_models:
                changes.append(f'+ agents.list[{agent[\"id\"]}].models.\"anthropic/claude-opus-4-6\"')
    for c in changes:
        print(c)
" 2>&1
}

# ── Display unified diff between original and patched files ──────────────────

show_diff() {
  local label="$1"
  local original="$2"
  local patched="$3"

  echo -e "  ${BOLD}${label}${NC}"
  echo ""

  if command -v diff &>/dev/null; then
    # Use color diff if available
    if diff --color=always "$original" "$patched" &>/dev/null 2>&1; then
      local d
      d=$(diff --color=always -u "$original" "$patched" 2>/dev/null || true)
      if [[ -z "$d" ]]; then
        echo -e "${DIM}    No changes.${NC}"
      else
        echo "$d" | head -60
        local total_lines
        total_lines=$(echo "$d" | wc -l)
        if (( total_lines > 60 )); then
          echo -e "${DIM}    ... (${total_lines} lines total — showing first 60)${NC}"
        fi
      fi
    else
      diff -u "$original" "$patched" 2>/dev/null | head -60 || true
    fi
  else
    echo -e "${DIM}    diff utility not available — install diffutils for change previews.${NC}"
  fi
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  banner

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}${BOLD}  ─── DRY RUN — no files will be modified ───${NC}"
    echo ""
  fi

  # ── Rollback ─────────────────────────────────────────────────────────
  if [[ "$ROLLBACK" == true ]]; then
    do_rollback
    exit 0
  fi

  # ── Step 1: Detect environment ───────────────────────────────────────
  echo -e "${BOLD}[1/7] Detecting environment${NC}"
  echo ""
  detect_cli
  detect_catalog
  detect_config
  echo ""

  # ── Step 2: Show what we protect ─────────────────────────────────────
  echo -e "${BOLD}[2/7] Verifying protected files${NC}"
  echo ""
  show_protected_files

  # ── Step 3: Compatibility ────────────────────────────────────────────
  echo -e "${BOLD}[3/7] Running compatibility checks${NC}"
  echo ""
  check_compat
  echo ""

  # ── Step 4: Generate patches (temp files — nothing written yet) ─────
  echo -e "${BOLD}[4/7] Generating patches${NC}"
  echo ""

  tmpdir=$(mktemp -d)
  trap 'rm -rf "${tmpdir:-}"' EXIT

  # Catalog patch
  info "Patching model catalog..."
  cp "$CATALOG_FILE" "${tmpdir}/catalog.original"
  cp "$CATALOG_FILE" "${tmpdir}/catalog.patched"
  local catalog_result
  catalog_result=$(generate_patched_catalog "${tmpdir}/catalog.original" "${tmpdir}/catalog.patched" 2>&1)
  if [[ $? -ne 0 ]]; then
    fatal "Catalog patch failed:\n${catalog_result}"
  fi
  success "$catalog_result"

  # Config patch (unless --add-only)
  local config_result="(skipped — --add-only)"
  if [[ "$ADD_ONLY" == false ]]; then
    info "Merging config (additive only)..."

    if [[ -f "$CONFIG_FILE" ]]; then
      cp "$CONFIG_FILE" "${tmpdir}/config.original"
    else
      echo "{}" > "${tmpdir}/config.original"
    fi
    cp "${tmpdir}/config.original" "${tmpdir}/config.patched"

    config_result=$(generate_patched_config "${tmpdir}/config.original" "${tmpdir}/config.patched" "$SET_PRIMARY" 2>&1)
    if [[ $? -ne 0 ]]; then
      fatal "Config patch failed:\n${config_result}"
    fi
    success "Config: ${config_result}"
  else
    info "Skipping config (--add-only)"
  fi
  echo ""

  # ── Step 5: Show diffs ──────────────────────────────────────────────
  echo -e "${BOLD}[5/7] Review proposed changes${NC}"
  echo ""

  show_diff "Model catalog (models.generated.js)" "${tmpdir}/catalog.original" "${tmpdir}/catalog.patched"

  if [[ "$ADD_ONLY" == false && -f "${tmpdir}/config.patched" ]]; then
    show_diff "Config ($(basename "$CONFIG_FILE"))" "${tmpdir}/config.original" "${tmpdir}/config.patched"
  fi

  # ── Confirm ─────────────────────────────────────────────────────────
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}${BOLD}  ─── DRY RUN COMPLETE — no files were modified ───${NC}"
    echo ""
    echo "  Review the diff above. To apply, re-run without --dry-run."
    exit 0
  fi

  if [[ "$FORCE" != true ]]; then
    echo -e "${BOLD}  Confirm changes${NC}"
    echo ""
    echo "    Will modify:"
    echo "      • ${CATALOG_FILE}"
    [[ "$ADD_ONLY" == false ]] && echo "      • ${CONFIG_FILE}"
    echo ""
    echo "    Will NOT modify:"
    echo "      • SOUL.md, IDENTITY.md, AGENTS.md, TOOLS.md, USER.md, MEMORY.md"
    echo "      • skills/, workspace/, sessions/, auth, credentials"
    echo "      • All other keys in your configuration"
    echo ""
    read -rp "  Apply? [y/N] " yn
    [[ "$yn" == [yY]* ]] || { info "Aborted. No changes made."; exit 0; }
    echo ""
  fi

  # ── Step 6: Backup & write ──────────────────────────────────────────
  echo -e "${BOLD}[6/7] Applying changes${NC}"
  echo ""

  # Backup
  backup_file "$CATALOG_FILE"
  [[ "$ADD_ONLY" == false ]] && backup_file "$CONFIG_FILE"

  # Write catalog
  cp "${tmpdir}/catalog.patched" "$CATALOG_FILE"
  success "Catalog written"

  # Write config
  if [[ "$ADD_ONLY" == false ]]; then
    local config_dir
    config_dir="$(dirname "$CONFIG_FILE")"
    mkdir -p "$config_dir"
    cp "${tmpdir}/config.patched" "$CONFIG_FILE"
    success "Config written"
  fi

  echo ""

  # ── Step 7: Restart ─────────────────────────────────────────────────
  echo -e "${BOLD}[7/7] Gateway restart${NC}"
  echo ""

  if [[ "$NO_RESTART" == true ]]; then
    warn "Skipping gateway restart (--no-restart)."
    echo ""
    warn "Catalog changes require a cold restart to take effect."
    warn "Run manually:"
    echo -e "  ${BOLD}${CLI_CMD} gateway stop && ${CLI_CMD} gateway start${NC}"
  else
    info "Cold-restarting gateway (required for catalog changes)..."
    $CLI_CMD gateway stop 2>&1 || warn "Gateway was not running."
    sleep 2
    $CLI_CMD gateway start 2>&1 || {
      err "Gateway failed to start. To diagnose:"
      echo -e "       ${BOLD}${CLI_CMD} gateway --verbose${NC}"
      echo ""
      echo -e "  To revert all changes:"
      echo -e "       ${BOLD}./install-opus46.sh --rollback${NC}"
      exit 1
    }
    sleep 3
    success "Gateway restarted"
  fi

  echo ""

  # ── Verify ──────────────────────────────────────────────────────────
  local catalog_ok=false config_ok=false

  grep -q '"claude-opus-4-6"' "$CATALOG_FILE" 2>/dev/null && catalog_ok=true
  if [[ "$ADD_ONLY" == true ]]; then
    config_ok=true
  elif grep -q "claude-opus-4-6" "$CONFIG_FILE" 2>/dev/null; then
    config_ok=true
  fi

  if [[ "$catalog_ok" == true && "$config_ok" == true ]]; then
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  ✓  Claude Opus 4.6 installed successfully${NC}"
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  else
    echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}${BOLD}  ⚠  Completed with warnings — verify manually${NC}"
    echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    [[ "$catalog_ok" == false ]] && err "claude-opus-4-6 not found in catalog after patching"
    [[ "$config_ok" == false ]]  && err "claude-opus-4-6 not found in config after patching"
  fi

  echo ""
  echo -e "  Usage:"
  echo -e "    Switch model:      ${BOLD}/model opus46${NC}"
  echo -e "    Full reference:    ${BOLD}/model anthropic/claude-opus-4-6${NC}"
  echo -e "    Verify:            ${BOLD}/model status${NC}"
  if [[ "$SET_PRIMARY" == false && "$ADD_ONLY" == false ]]; then
    echo ""
    echo -e "  Note: Your primary model was not changed."
    echo -e "  To set Opus 4.6 as default, re-run with ${BOLD}--set-primary${NC}"
  fi
  echo ""
  echo -e "  Rollback:            ${BOLD}./install-opus46.sh --rollback${NC}"
  echo ""
  echo -e "${DIM}  Note: npm update -g ${CLI_CMD} will overwrite the catalog.${NC}"
  echo -e "${DIM}  Re-run this installer after any package update.${NC}"
  echo ""
}

main "$@"
