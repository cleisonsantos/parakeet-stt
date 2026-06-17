#!/usr/bin/env bash
#
# install.sh — Install the Parakeet V3 STT plugin for Hermes Agent
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cleisonsantos/parakeet-stt/main/install.sh | bash
#
# Or run locally:
#   ./install.sh [--profile <name>]
#
set -euo pipefail

REPO="https://github.com/cleisonsantos/parakeet-stt.git"
PLUGIN_NAME="parakeet-stt"

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}ℹ${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1"; }

# ── Help ────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [--profile <name>]"
    echo ""
    echo "Options:"
    echo "  --profile <name>   Install under a named Hermes profile"
    echo "                     (default: ~/.hermes/plugins/)"
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

# ── Determine plugin directory ─────────────────────────────────────────────
if [[ -n "$PROFILE" ]]; then
    HERMES_HOME="${HERMES_HOME:-$HOME/.hermes/profiles/$PROFILE}"
else
    HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
fi

PLUGIN_DIR="$HERMES_HOME/plugins/$PLUGIN_NAME"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Parakeet V3 STT — Hermes Plugin        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Clone / update ─────────────────────────────────────────────────
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

# ── Step 2: Enable in Hermes config ────────────────────────────────────────
if command -v hermes &>/dev/null; then
    info "Enabling plugin via Hermes CLI..."
    hermes plugins enable "$PLUGIN_NAME" 2>/dev/null && ok "Plugin enabled" \
        || warn "Could not auto-enable. Run: hermes plugins enable $PLUGIN_NAME"
else
    warn "hermes CLI not found on PATH. Enable manually:"
    echo "  hermes plugins enable $PLUGIN_NAME"
fi

# ── Step 3: Install Python dependencies ────────────────────────────────────
info "Installing Python dependencies (transformers, torch, ...)"

# Try to find the Hermes venv
VENV=""
for candidate in "$HERMES_HOME/hermes-agent/.venv" \
                 "$HERMES_HOME/../hermes-agent/.venv" \
                 "$HOME/.hermes/hermes-agent/.venv" \
                 "$HOME/.hermes/hermes-agent/venv"; do
    if [[ -f "$candidate/bin/python3" ]]; then
        VENV="$candidate"
        break
    fi
done

if [[ -n "$VENV" ]] && command -v uv &>/dev/null; then
    ok "Found Hermes venv: $VENV"
    uv pip install --python "$VENV/bin/python3" \
        transformers torch soundfile librosa accelerate 2>&1 | tail -1
    ok "Dependencies installed"
elif command -v pip &>/dev/null; then
    warn "Using system pip (not Hermes venv)"
    pip install transformers torch soundfile librosa accelerate 2>&1 | tail -1
    ok "Dependencies installed (system)"
else
    err "Could not find pip or uv. Install manually:"
    echo "  uv pip install transformers torch soundfile librosa accelerate"
fi

# ── Step 4: Config hint ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✅ Parakeet V3 STT plugin installed!${NC}"
echo ""
echo "To activate, add to your config.yaml:"
echo ""
echo -e "  ${YELLOW}stt:${NC}"
echo -e "  ${YELLOW}  provider: parakeet${NC}"
echo -e "  ${YELLOW}  parakeet:${NC}"
echo -e "  ${YELLOW}    language: \"\"${NC}"
echo ""
echo "Then restart the gateway:"
echo -e "  ${CYAN}hermes gateway restart${NC}"
echo ""
