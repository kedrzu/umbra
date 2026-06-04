#!/bin/bash
set -e

# Gmail OAuth Setup Script
# Run this to authenticate Gmail accounts

# This script lives at the project root; resolve it regardless of the caller's cwd.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Gmail OAuth Setup${NC}"
echo

# Source .env if it exists
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
fi

# Check credentials
if [ -z "$GMAIL_CREDENTIALS_PATH" ] || [ ! -f "$GMAIL_CREDENTIALS_PATH" ]; then
    echo -e "${RED}Error: Gmail credentials not found${NC}"
    echo "Set GMAIL_CREDENTIALS_PATH in .env or ensure the file exists"
    exit 1
fi

echo -e "${GREEN}✓ Gmail credentials found: $GMAIL_CREDENTIALS_PATH${NC}"
echo

# Start the Gmail container
echo "Starting Gmail MCP container..."
cd "$PROJECT_DIR"
docker compose up -d gmail

# Wait for container to be ready
sleep 3

echo
echo -e "${YELLOW}Gmail OAuth is ready!${NC}"
echo
echo "To authenticate accounts, visit:"
echo -e "  ${BLUE}http://localhost:${MCP_GMAIL_PORT:-4002}/auth${NC}"
echo
echo "To manage existing accounts:"
echo -e "  ${BLUE}http://localhost:${MCP_GMAIL_PORT:-4002}/accounts${NC}"
echo
echo -e "${YELLOW}Press Enter when done to stop the container, or Ctrl+C to keep it running...${NC}"
read

docker compose stop gmail
echo -e "${GREEN}Done!${NC}"
