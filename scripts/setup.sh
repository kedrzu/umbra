#!/bin/bash
set -e

echo "=== Caracas AI Assistant Setup ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$HOME/.config/caracas"
VAULT_PATH="/Users/kedrzu/Library/Mobile Documents/iCloud~md~obsidian/Documents/kedrzu"

# Create config directory
echo "Creating config directory..."
mkdir -p "$CONFIG_DIR"

# Check for required tools
echo ""
echo "Checking required tools..."

check_tool() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 found"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 not found"
        return 1
    fi
}

MISSING_TOOLS=0

check_tool "node" || MISSING_TOOLS=1
check_tool "npm" || MISSING_TOOLS=1
check_tool "npx" || MISSING_TOOLS=1

# Check for qmd (optional but recommended)
if ! check_tool "qmd"; then
    echo -e "  ${YELLOW}!${NC} qmd is optional but recommended for fast vault search"
    echo "    Install with: bun install -g github:tobi/qmd"
fi

if [ $MISSING_TOOLS -eq 1 ]; then
    echo ""
    echo -e "${RED}Error: Missing required tools. Please install them first.${NC}"
    exit 1
fi

# Build obsidian-vault MCP server
echo ""
echo "Building obsidian-vault MCP server..."
cd "$PROJECT_ROOT/mcp-servers/obsidian-vault"
npm install
npm run build
echo -e "${GREEN}✓${NC} obsidian-vault MCP server built"

# Setup qmd if available
if command -v qmd &> /dev/null; then
    echo ""
    echo "Setting up qmd for Obsidian vault search..."

    # Check if collection already exists
    if qmd collection list 2>/dev/null | grep -q "obsidian"; then
        echo "  Collection 'obsidian' already exists"
    else
        qmd collection add "$VAULT_PATH" --name obsidian
        echo -e "${GREEN}✓${NC} Added vault collection"
    fi

    # Add context
    qmd context add qmd://obsidian "Personal knowledge base, notes, projects, and AI assistant memory" 2>/dev/null || true

    # Generate embeddings
    echo "Generating embeddings (this may take a while)..."
    qmd embed
    echo -e "${GREEN}✓${NC} qmd configured"
fi

# Setup instructions
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. ${YELLOW}Configure Gmail MCP server${NC}"
echo "   The Gmail MCP server needs to be forked and set up separately."
echo "   See: https://github.com/PaulFidika/gmail-mcp-server"
echo "   After setup, add credentials to: $CONFIG_DIR/gmail-credentials.json"
echo ""
echo "2. ${YELLOW}Configure Google Calendar${NC}"
echo "   The calendar MCP server (@nspady/google-calendar-mcp) will prompt"
echo "   for OAuth authentication on first use."
echo ""
echo "3. ${YELLOW}Configure Todoist${NC}"
echo "   The official Todoist MCP (https://ai.todoist.net/mcp) will prompt"
echo "   for OAuth authentication on first use."
echo ""
echo "4. ${YELLOW}Test the setup${NC}"
echo "   cd $PROJECT_ROOT"
echo "   claude  # Start Claude Code in this directory"
echo "   Then try: /daily-dashboard"
echo ""
echo "Configuration files:"
echo "  - CLAUDE.md: Assistant instructions"
echo "  - .mcp.json: MCP server configuration"
echo "  - .claude/settings.json: Permission rules"
echo "  - .claude/skills/*: Available skills"
echo ""
echo -e "${GREEN}Happy assistanting! 🤖${NC}"
