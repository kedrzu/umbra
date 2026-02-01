#!/bin/bash
set -e

# Umbra Personal Assistant - Docker Setup Script
# This script helps set up the Docker environment and OAuth authentication

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Umbra Personal Assistant - Docker Setup              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not available${NC}"
    echo "Please ensure Docker Compose is installed"
    exit 1
fi

echo -e "${GREEN}✓ Docker and Docker Compose are installed${NC}"

# Check for .env file
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo -e "${YELLOW}Creating .env file from .env.example...${NC}"
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    echo -e "${YELLOW}Please edit $PROJECT_DIR/.env with your configuration${NC}"
    echo
    echo "Required settings:"
    echo "  - OBSIDIAN_VAULT_PATH: Path to your Obsidian vault"
    echo "  - GMAIL_CREDENTIALS_PATH: Path to Gmail OAuth credentials"
    echo "  - CALENDAR_CREDENTIALS_PATH: Path to Calendar OAuth credentials"
    echo "  - CLAUDE_CONFIG_PATH: Path to ~/.claude (for subscription auth)"
    echo
    read -p "Press Enter after editing .env to continue..."
fi

# Source .env file
source "$PROJECT_DIR/.env"

# Validate required paths
echo -e "${YELLOW}Validating configuration...${NC}"

if [ ! -d "$OBSIDIAN_VAULT_PATH" ]; then
    echo -e "${RED}Error: Obsidian vault not found at: $OBSIDIAN_VAULT_PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Obsidian vault found${NC}"

if [ ! -f "$GMAIL_CREDENTIALS_PATH" ]; then
    echo -e "${YELLOW}Warning: Gmail credentials not found at: $GMAIL_CREDENTIALS_PATH${NC}"
    echo "You'll need to set up Gmail OAuth credentials from Google Cloud Console"
fi

if [ ! -f "$CALENDAR_CREDENTIALS_PATH" ]; then
    echo -e "${YELLOW}Warning: Calendar credentials not found at: $CALENDAR_CREDENTIALS_PATH${NC}"
    echo "You'll need to set up Calendar OAuth credentials from Google Cloud Console"
fi

# Check Claude authentication
if [ -d "$CLAUDE_CONFIG_PATH" ]; then
    echo -e "${GREEN}✓ Claude config directory found${NC}"
else
    echo -e "${YELLOW}Warning: Claude config not found at: $CLAUDE_CONFIG_PATH${NC}"
    echo "Run 'claude login' on your host machine first to authenticate"
fi

# Build images
echo
echo -e "${YELLOW}Building Docker images...${NC}"
cd "$PROJECT_DIR"
docker compose build

echo -e "${GREEN}✓ Docker images built${NC}"

# Function to setup OAuth for a service
setup_oauth() {
    local service=$1
    local port=$2
    local name=$3

    echo
    echo -e "${BLUE}Setting up $name OAuth...${NC}"
    echo "Starting $service container..."

    docker compose up -d $service

    echo
    echo -e "${YELLOW}Please visit http://localhost:$port/auth to authenticate${NC}"
    echo "After authentication, you can add more accounts at http://localhost:$port/accounts"
    echo
    read -p "Press Enter when done with $name authentication..."
}

# Ask about OAuth setup
echo
echo -e "${BLUE}OAuth Setup${NC}"
echo "Would you like to set up OAuth for Gmail and Calendar now?"
echo "This requires browser access to complete the OAuth flow."
echo
read -p "Set up OAuth now? (y/n): " setup_oauth_now

if [ "$setup_oauth_now" = "y" ] || [ "$setup_oauth_now" = "Y" ]; then
    # Start Gmail for OAuth
    if [ -f "$GMAIL_CREDENTIALS_PATH" ]; then
        setup_oauth "gmail" "4002" "Gmail"
    fi

    # Start Calendar for OAuth
    if [ -f "$CALENDAR_CREDENTIALS_PATH" ]; then
        setup_oauth "calendar" "4003" "Calendar"
    fi

    # Stop OAuth containers
    echo
    echo -e "${YELLOW}Stopping OAuth setup containers...${NC}"
    docker compose down
fi

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo "To start the full stack:"
echo -e "  ${BLUE}docker compose up -d${NC}"
echo
echo "To run Claude Code interactively:"
echo -e "  ${BLUE}docker compose run --rm claude${NC}"
echo
echo "To view logs:"
echo -e "  ${BLUE}docker compose logs -f${NC}"
echo
echo "For more information, see docs/DOCKER.md"
