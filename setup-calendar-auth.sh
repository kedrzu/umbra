#!/bin/bash
set -e

# Calendar OAuth Setup Script
# Run this on the HOST machine to authenticate Google Calendar accounts
# (The calendar MCP auth server only binds to localhost, so Docker doesn't work)

# This script lives at the project root; resolve it regardless of the caller's cwd.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Calendar OAuth Setup${NC}"
echo

# Source .env if it exists
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
fi

# Check credentials
if [ -z "$CALENDAR_CREDENTIALS_PATH" ] || [ ! -f "$CALENDAR_CREDENTIALS_PATH" ]; then
    echo -e "${RED}Error: Calendar credentials not found${NC}"
    echo "Set CALENDAR_CREDENTIALS_PATH in .env or ensure the file exists"
    exit 1
fi

echo -e "${GREEN}✓ Calendar credentials found: $CALENDAR_CREDENTIALS_PATH${NC}"

# Check npx
if ! command -v npx &> /dev/null; then
    echo -e "${RED}Error: npx is not installed${NC}"
    echo "Please install Node.js first"
    exit 1
fi

# Set credentials for the auth command
export GOOGLE_OAUTH_CREDENTIALS="$CALENDAR_CREDENTIALS_PATH"

# Token path
TOKENS_DIR="${CALENDAR_TOKENS_PATH:-$HOME/.config/google-calendar-mcp}"
mkdir -p "$TOKENS_DIR"

echo
echo "Usage:"
echo "  1) Add default account:    $0"
echo "  2) Add named account:      $0 <account-name>"
echo "  3) List accounts:          $0 --list"
echo
echo "Examples:"
echo "  $0 personal"
echo "  $0 work"
echo

# Handle arguments
case "${1:-}" in
    --list|-l)
        echo -e "${BLUE}Checking existing accounts...${NC}"
        if [ -f "$TOKENS_DIR/tokens.json" ]; then
            echo -e "${GREEN}Tokens file exists at: $TOKENS_DIR/tokens.json${NC}"
            echo
            echo "Accounts in token file:"
            # Try to parse account names from the JSON
            if command -v jq &> /dev/null; then
                jq -r 'keys[]' "$TOKENS_DIR/tokens.json" 2>/dev/null || echo "  (could not parse accounts)"
            else
                echo "  (install jq to see account names)"
            fi
        else
            echo -e "${YELLOW}No tokens file found at: $TOKENS_DIR/tokens.json${NC}"
        fi
        exit 0
        ;;
    --help|-h)
        echo "Calendar OAuth Setup"
        echo
        echo "Options:"
        echo "  <account-name>  Add a new account with the given name"
        echo "  --list, -l      List existing accounts"
        echo "  --help, -h      Show this help"
        exit 0
        ;;
    "")
        echo -e "${BLUE}Adding default account...${NC}"
        echo -e "${YELLOW}A browser window will open for Google OAuth.${NC}"
        echo
        npx @cocal/google-calendar-mcp auth
        ;;
    *)
        ACCOUNT_NAME="$1"
        echo -e "${BLUE}Adding account: $ACCOUNT_NAME${NC}"
        echo -e "${YELLOW}A browser window will open for Google OAuth.${NC}"
        echo
        npx @cocal/google-calendar-mcp auth "$ACCOUNT_NAME"
        ;;
esac

# Verify tokens
echo
if [ -f "$TOKENS_DIR/tokens.json" ]; then
    echo -e "${GREEN}✓ Tokens saved to: $TOKENS_DIR/tokens.json${NC}"
    echo
    echo "To use in Docker, restart the calendar container:"
    echo -e "  ${BLUE}docker compose restart calendar${NC}"
else
    echo -e "${YELLOW}Warning: Token file not found${NC}"
    echo "Expected at: $TOKENS_DIR/tokens.json"
fi
