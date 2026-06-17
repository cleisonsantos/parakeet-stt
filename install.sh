#!/usr/bin/env bash
#
# install.sh — Install the Parakeet V3 STT Plugin for Hermes Agent
#
# Detects Hermes installation, finds the right profile/venv,
# clones the plugin, installs dependencies, and enables it.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cleisonsantos/parakeet-stt/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/cleisonsantos/parakeet-stt/main/install.sh | bash -s -- --profile sureka-cloud
#
set -euo pipefail

REPO="https://github.com/cleisonsantos/parakeet-stt.git"
PLUGIN_NAME="parakeet-stt"

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m' # No Color

info()  { echo -e "${CYAN}ℹ${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1"; }
bail()  { err "$1"; exit 1; }

# ── Help ────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [--profile <name>]"
    echo ""
    echo "Options:"
    echo "  --profile <name>   Install under a named Hermes profile"
    echo "                     (default: auto-detect)"
    echo "  --help             Show this help"
    exit 0
}

# ── Parse args ──────────────────────────────────────────────────────────────
PROFILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
done

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Parakeet V3 STT — Hermes Plugin        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 0: Check if Hermes is installed ───────────────────────────────────
HERMES_BIN=""
if command -v hermes &>/dev/null; then
    HERMES_BIN=$(command -v hermes)
    ok "Hermes CLI found: $HERMES_BIN"
else
    # Try common locations
    for candidate in \
        "$HOME/.hermes/hermes-agent/venv/bin/hermes" \
        "$HOME/.hermes/hermes-agent/.venv/bin/hermes" \
        "/opt/hermes/bin/hermes" \
        "/usr/local/bin/hermes"; do
        if [[ -x "$candidate" ]]; then
            HERMES_BIN="$candidate"
            break
        fi
    done
    if [[ -z "$HERMES_BIN" ]]; then
        bail "Hermes Agent is not installed. Install it first: curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
    fi
    info "Hermes CLI found at: $HERMES_BIN"
fi

# ── Step 1: Detect Hermes home ────────────────────────────────────────────
# Preferred: use --profile flag
if [[ -n "$PROFILE" ]]; then
    HERMES_HOME="$HOME/.hermes/profiles/$PROFILE"
    info "Using profile: $PROFILE → $HERMES_HOME"
else
    # Try to detect active profile from hermes CLI
    DETECTED_PROFILE=$("$HERMES_BIN" config get model.provider 2>/dev/null && echo "" || true)
    # Check if there's a default profile configured
    if [[ -f "$HOME/.hermes/config.yaml" ]]; then
        # Look for profile in common locations
        if [[ -d "$HOME/.hermes/profiles" ]]; then
            # Check if current directory has a .hermes-home or similar
            HERMES_HOME="$HOME/.hermes"
        else
            HERMES_HOME="$HOME/.hermes"
        fi
    else
        HERMES_HOME="$HOME/.hermes"
    fi
fi
# Fallback: if HERMES_HOME env var is set, honour it
HERMES_HOME="${HERMES_HOME:-${HERMES_HOME:-$HOME/.hermes}}"

PLUGIN_DIR="$HERMES_HOME/plugins/$PLUGIN_NAME"
ok "Plugin directory: $PLUGIN_DIR"

# ── Step 2: Find the Hermes venv ───────────────────────────────────────────
VENV=""
for candidate in \
    "$(dirname "$(dirname "$HERMES_BIN")")" \
    "$HERMES_HOME/hermes-agent/.venv" \
    "$HERMES_HOME/hermes-agent/venv" \
    "$HOME/.hermes/hermes-agent/.venv" \
    "$HOME/.hermes/hermes-agent/venv"; do
    if [[ -f "$candidate/bin/python3" ]]; then
        VENV="$candidate"
        break
    fi
done

if [[ -z "$VENV" ]]; then
    warn "Hermes venv not found. Will use system Python (not recommended)."
    PYTHON="python3"
else
    PYTHON="$VENV/bin/python3"
    ok "Hermes venv: $VENV"
fi

# ── Step 3: Clone / update plugin ──────────────────────────────────────────
if [[ -d "$PLUGIN_DIR/.git" ]]; then
    info "Plugin already installed. Updating..."
    cd "$PLUGIN_DIR"
    git pull --ff-only origin main
    ok "Updated to latest version"
else
    info "Installing plugin to: $PLUGIN_DIR"
    mkdir -p "$(dirname "$PLUGIN_DIR")"
    git clone "$REPO" "$PLUGIN_DIR"
    ok "Plugin cloned"
fi

# ── Step 4: Enable in Hermes config ────────────────────────────────────────
ENABLED=false
if command -v hermes &>/dev/null; then
    info "Enabling plugin via Hermes CLI..."
    if hermes plugins enable "$PLUGIN_NAME" 2>/dev/null; then
        ok "Plugin enabled"
        ENABLED=true
    else
        warn "Could not auto-enable. Run: hermes plugins enable $PLUGIN_NAME"
    fi
else
    # Direct config edit fallback
    CONFIG_FILE="$HERMES_HOME/config.yaml"
    if [[ -f "$CONFIG_FILE" ]]; then
        # Try to add to plugins.enabled list
        if grep -q "^plugins:" "$CONFIG_FILE"; then
            if grep -q "parakeet-stt" "$CONFIG_FILE"; then
                ok "Plugin already in plugins.enabled"
            else
                # Use Python to safely edit yaml
                "$PYTHON" -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
cfg.setdefault('plugins', {}).setdefault('enabled', [])
if '$PLUGIN_NAME' not in cfg['plugins']['enabled']:
    cfg['plugins']['enabled'].append('$PLUGIN_NAME')
    with open('$CONFIG_FILE', 'w') as f:
        yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)
    print('OK')
" 2>/dev/null && ok "Plugin enabled in config" || warn "Could not edit config"
        fi
    fi
fi

# ── Step 5: Install Python dependencies ────────────────────────────────────
DEPS="transformers torch soundfile librosa accelerate"
info "Installing Python dependencies: $DEPS"

if command -v uv &>/dev/null; then
    if [[ -n "$VENV" ]]; then
        uv pip install --python "$PYTHON" $DEPS 2>&1 | tail -2
        ok "Dependencies installed in Hermes venv"
    else
        uv pip install $DEPS 2>&1 | tail -2
        ok "Dependencies installed via uv"
    fi
elif command -v pip &>/dev/null; then
    warn "Using pip (not uv). Consider installing uv for faster installs."
    pip install $DEPS 2>&1 | tail -2
    ok "Dependencies installed"
else
    warn "Neither pip nor uv found. Install manually:"
    echo "  uv pip install $DEPS"
fi

# ── Step 6: Verify ─────────────────────────────────────────────────────────
info "Verifying installation..."
PLUGIN_YAML="$PLUGIN_DIR/plugin.yaml"
PLUGIN_INIT="$PLUGIN_DIR/__init__.py"
OK=true

if [[ ! -f "$PLUGIN_YAML" ]]; then err "Missing: $PLUGIN_YAML"; OK=false; fi
if [[ ! -f "$PLUGIN_INIT" ]]; then err "Missing: $PLUGIN_INIT"; OK=false; fi

if $OK; then
    # Verify deps are importable
    if "$PYTHON" -c "import transformers; import torch" 2>/dev/null; then
        ok "Python dependencies are importable"
    else
        warn "Dependencies check failed. Run: uv pip install $DEPS"
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ Parakeet V3 STT plugin installed!      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Location:${NC}  $PLUGIN_DIR"
    echo ""
    echo -e "  ${BOLD}To activate,${NC} add to your ${YELLOW}config.yaml${NC}:"
    echo ""
    echo -e "    ${YELLOW}stt:${NC}"
    echo -e "    ${YELLOW}  provider: parakeet${NC}"
    echo -e "    ${YELLOW}  parakeet:${NC}"
    echo -e "    ${YELLOW}    language: \"\"${NC}"
    echo ""
    echo -e "  ${BOLD}Then restart the gateway:${NC}"
    echo -e "    ${CYAN}hermes gateway restart${NC}"
    echo ""
else
    bail "Installation incomplete — see errors above."
fi
