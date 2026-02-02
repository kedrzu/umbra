#!/bin/bash
set -e

# Umbra Personal Assistant - Setup Script
# Idempotent script that sets up everything needed to run the assistant

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSISTANT_DIR="$PROJECT_ROOT/assistant"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Umbra Personal Assistant - Setup                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# ==========================================
# Check required tools
# ==========================================
echo -e "${YELLOW}Checking prerequisites...${NC}"

check_tool() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 not found"
        return 1
    fi
}

MISSING_TOOLS=0

check_tool "docker" || MISSING_TOOLS=1
docker compose version &> /dev/null && echo -e "  ${GREEN}✓${NC} docker compose" || { echo -e "  ${RED}✗${NC} docker compose not found"; MISSING_TOOLS=1; }

# Check for bun (needed for qmd)
if ! check_tool "bun"; then
    echo -e "  ${YELLOW}!${NC} bun not found - needed for qmd installation"
    echo "    Install with: curl -fsSL https://bun.sh/install | bash"
    MISSING_TOOLS=1
fi

if [ $MISSING_TOOLS -eq 1 ]; then
    echo
    echo -e "${RED}Error: Missing required tools. Please install them first.${NC}"
    exit 1
fi

# ==========================================
# Check for .env file
# ==========================================
echo
echo -e "${YELLOW}Checking configuration...${NC}"

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo "  Creating .env file from .env.example..."
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    echo -e "  ${YELLOW}!${NC} Please edit $PROJECT_ROOT/.env with your configuration"
    echo
    echo "  Required settings:"
    echo "    - OBSIDIAN_VAULT_PATH: Path to your Obsidian vault"
    echo "    - GMAIL_CREDENTIALS_PATH: Path to Gmail OAuth credentials"
    echo "    - CALENDAR_CREDENTIALS_PATH: Path to Calendar OAuth credentials"
    echo
    read -p "  Press Enter after editing .env to continue..."
else
    echo -e "  ${GREEN}✓${NC} .env file exists"
fi

# Source .env file
set -a
source "$PROJECT_ROOT/.env"
set +a

# Validate paths
if [ -d "$OBSIDIAN_VAULT_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} Obsidian vault found: $OBSIDIAN_VAULT_PATH"
else
    echo -e "  ${RED}✗${NC} Obsidian vault not found at: $OBSIDIAN_VAULT_PATH"
    exit 1
fi

if [ -f "$GMAIL_CREDENTIALS_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} Gmail credentials found"
else
    echo -e "  ${YELLOW}!${NC} Gmail credentials not found (optional)"
fi

if [ -f "$CALENDAR_CREDENTIALS_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} Calendar credentials found"
else
    echo -e "  ${YELLOW}!${NC} Calendar credentials not found (optional)"
fi

# ==========================================
# Install qmd
# ==========================================
echo
echo -e "${YELLOW}Setting up qmd (semantic search for Obsidian)...${NC}"

if command -v qmd &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} qmd already installed"
else
    echo "  Installing qmd..."
    bun add -g github:tobi/qmd

    if command -v qmd &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} qmd installed"
    else
        echo -e "  ${RED}✗${NC} qmd installation failed"
        echo "    Try manually: bun add -g github:tobi/qmd"
        echo "    Make sure bun's global bin directory is in your PATH"
    fi
fi

# Configure qmd collection (if qmd is available)
if command -v qmd &> /dev/null; then
    echo "  Configuring qmd collection..."

    if qmd collection list 2>/dev/null | grep -q "obsidian"; then
        echo -e "  ${GREEN}✓${NC} Collection 'obsidian' already exists"
    else
        qmd collection add "$OBSIDIAN_VAULT_PATH" --name obsidian 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Added vault collection"
    fi

    # Generate embeddings (skip if already done recently)
    echo "  Checking embeddings..."
    qmd embed 2>/dev/null || echo -e "  ${YELLOW}!${NC} Embedding generation skipped or failed"
fi

# ==========================================
# Generate configuration from templates
# ==========================================
echo
echo -e "${YELLOW}Generating configuration files from templates...${NC}"

# Get absolute path to qmd
QMD_PATH=$(command -v qmd 2>/dev/null || echo "qmd")

# Set default ports
MCP_OBSIDIAN_PORT="${MCP_OBSIDIAN_PORT:-4001}"
MCP_GMAIL_PORT="${MCP_GMAIL_PORT:-4002}"
MCP_CALENDAR_PORT="${MCP_CALENDAR_PORT:-4003}"

# Export all variables for envsubst
export OBSIDIAN_VAULT_PATH MCP_OBSIDIAN_PORT MCP_GMAIL_PORT MCP_CALENDAR_PORT QMD_PATH

# Generate .mcp.json from template
envsubst < "$ASSISTANT_DIR/.mcp.template.json" > "$ASSISTANT_DIR/.mcp.json"
echo -e "  ${GREEN}✓${NC} Generated .mcp.json"

# Generate .claude/settings.json from template
# First make it writable if it exists and is read-only
if [ -f "$ASSISTANT_DIR/.claude/settings.json" ]; then
    chmod 644 "$ASSISTANT_DIR/.claude/settings.json" 2>/dev/null || true
fi

envsubst < "$ASSISTANT_DIR/.claude/settings.template.json" > "$ASSISTANT_DIR/.claude/settings.json"

# Make settings read-only to prevent agent from modifying its own restrictions
chmod 444 "$ASSISTANT_DIR/.claude/settings.json"
echo -e "  ${GREEN}✓${NC} Generated .claude/settings.json (read-only)"

# ==========================================
# Build Docker images
# ==========================================
echo
echo -e "${YELLOW}Building Docker MCP servers...${NC}"
cd "$PROJECT_ROOT"
docker compose build

echo -e "  ${GREEN}✓${NC} Docker images built"

# ==========================================
# Start/restart containers
# ==========================================
echo
echo -e "${YELLOW}Starting MCP servers...${NC}"

# Check if containers are already running
if docker compose ps --status running 2>/dev/null | grep -q "umbra"; then
    echo "  Restarting containers..."
    docker compose up -d --force-recreate
else
    echo "  Starting containers..."
    docker compose up -d
fi

# Wait for health checks
echo "  Waiting for servers to be ready..."
sleep 3

# Check health
check_server() {
    local name=$1
    local port=$2
    if curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $name (port $port)"
        return 0
    else
        echo -e "  ${YELLOW}!${NC} $name (port $port) - may still be starting"
        return 1
    fi
}

check_server "obsidian" "${MCP_OBSIDIAN_PORT:-4001}"
check_server "gmail" "${MCP_GMAIL_PORT:-4002}"
check_server "calendar" "${MCP_CALENDAR_PORT:-4003}"

# ==========================================
# OAuth Setup (optional)
# ==========================================
echo
echo -e "${BLUE}OAuth Setup${NC}"

# Check if Gmail needs auth
GMAIL_NEEDS_AUTH=false
if [ -f "$GMAIL_CREDENTIALS_PATH" ]; then
    # Check if tokens exist
    GMAIL_TOKEN_CHECK=$(curl -s "http://localhost:${MCP_GMAIL_PORT:-4002}/health" 2>/dev/null | grep -o '"accounts":\[[^]]*\]' || echo "")
    if [ "$GMAIL_TOKEN_CHECK" = '"accounts":[]' ]; then
        GMAIL_NEEDS_AUTH=true
    fi
fi

# Check if Calendar needs auth
CALENDAR_NEEDS_AUTH=false
CALENDAR_TOKEN_PATH="${CALENDAR_TOKENS_PATH:-$HOME/.config/google-calendar-mcp}/tokens.json"
if [ -f "$CALENDAR_CREDENTIALS_PATH" ] && [ ! -f "$CALENDAR_TOKEN_PATH" ]; then
    CALENDAR_NEEDS_AUTH=true
fi

if [ "$GMAIL_NEEDS_AUTH" = true ] || [ "$CALENDAR_NEEDS_AUTH" = true ]; then
    echo "Some services need OAuth authentication."
    read -p "Set up OAuth now? (y/n): " setup_oauth_now

    if [ "$setup_oauth_now" = "y" ] || [ "$setup_oauth_now" = "Y" ]; then
        if [ "$GMAIL_NEEDS_AUTH" = true ]; then
            echo
            echo -e "${YELLOW}Gmail OAuth:${NC}"
            echo -e "  Visit ${BLUE}http://localhost:${MCP_GMAIL_PORT:-4002}/auth${NC} to authenticate"
            read -p "  Press Enter when done..."
        fi

        if [ "$CALENDAR_NEEDS_AUTH" = true ]; then
            echo
            echo -e "${YELLOW}Calendar OAuth:${NC}"
            if command -v npx &> /dev/null; then
                export GOOGLE_OAUTH_CREDENTIALS="$CALENDAR_CREDENTIALS_PATH"
                npx @cocal/google-calendar-mcp auth
            else
                echo -e "  ${YELLOW}!${NC} npx not found - run manually:"
                echo "    GOOGLE_OAUTH_CREDENTIALS=\"$CALENDAR_CREDENTIALS_PATH\" npx @cocal/google-calendar-mcp auth"
            fi
        fi
    fi
else
    echo -e "${GREEN}✓${NC} All services authenticated"
fi

# ==========================================
# Done
# ==========================================
echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo "To use the assistant:"
echo
echo "  Run Claude Code from the assistant directory:"
echo -e "     ${BLUE}cd $ASSISTANT_DIR && claude${NC}"
echo
echo "  Try a skill:"
echo -e "     ${BLUE}/daily-dashboard${NC}"
echo
echo "To manage MCP servers:"
echo -e "  View logs:    ${BLUE}docker compose logs -f${NC}"
echo -e "  Stop:         ${BLUE}docker compose down${NC}"
echo -e "  Restart:      ${BLUE}$SCRIPT_DIR/setup.sh${NC}"
echo
