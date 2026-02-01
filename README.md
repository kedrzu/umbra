# Docker Setup Guide

This guide explains how to run the Umbra Personal Assistant in Docker containers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DOCKER COMPOSE NETWORK                           │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                     claude (Claude Code)                            │ │
│  │  - Claude Code CLI (sandboxed)                                      │ │
│  │  - qmd (semantic search)                                            │ │
│  │  - Read-only vault access                                           │ │
│  │  - Read-write assistant/ folder (self-modifying)                    │ │
│  │  - Connects to MCPs via HTTP/SSE                                    │ │
│  └──────────────────────────────────────────────────────────────────┬─┘ │
│                                                                      │   │
│         ┌────────────────────┬───────────────────┬──────────────────┘   │
│         ▼                    ▼                   ▼                       │
│  ┌─────────────┐      ┌─────────────┐     ┌─────────────┐              │
│  │ obsidian    │      │   gmail     │     │  calendar   │              │
│  │   :4001     │      │   :4002     │     │   :4003     │              │
│  └─────────────┘      └─────────────┘     └─────────────┘              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Docker Desktop** or Docker Engine with Docker Compose
2. **Anthropic account** with Claude Code subscription (or API key)
3. **Google Cloud credentials** for Gmail and Calendar APIs
4. **Obsidian vault** accessible on your filesystem

## Quick Start

### 1. Clone and Configure

```bash
cd umbra

# Copy environment template
cp .env.example .env

# Edit .env with your paths
nano .env
```

### 2. Authenticate Claude Code

Claude Code requires authentication. Run this on your host machine first:

```bash
# Install Claude Code if not already installed
npm install -g @anthropic-ai/claude-code

# Login with your Anthropic account
claude login
```

Your credentials are saved to `~/.claude/` and will be mounted into the container.

### 3. Run Setup Script

```bash
./scripts/docker-setup.sh
```

This will:

- Validate your configuration
- Build Docker images
- Guide you through OAuth setup for Gmail and Calendar

### 4. Start the Stack

```bash
# Start all services
docker compose up -d

# Run Claude Code interactively
docker compose run --rm claude
```

## Configuration

### Environment Variables (.env)

```bash
# Anthropic Authentication
# Option 1: API Key
ANTHROPIC_API_KEY=sk-ant-api03-your-key

# Option 2: Subscription (via mounted ~/.claude config)
CLAUDE_CONFIG_PATH=${HOME}/.claude

# Paths
OBSIDIAN_VAULT_PATH=/path/to/your/obsidian/vault

# OAuth Credentials (from Google Cloud Console)
GMAIL_CREDENTIALS_PATH=${HOME}/.config/umbra/gmail-credentials.json
CALENDAR_CREDENTIALS_PATH=${HOME}/.config/umbra/calendar-credentials.json

# Ports (optional, for debugging)
MCP_OBSIDIAN_PORT=4001
MCP_GMAIL_PORT=4002
MCP_CALENDAR_PORT=4003
```

### Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable Gmail API and Google Calendar API
4. Create OAuth 2.0 credentials (Desktop app type)
5. Download credentials JSON files
6. Save as:
   - `~/.config/umbra/gmail-credentials.json`
   - `~/.config/umbra/calendar-credentials.json`

## Usage

### Interactive Mode

```bash
# Start Claude Code with all MCPs
docker compose run --rm claude
```

### Running Commands

```bash
# Run a specific skill
docker compose run --rm claude --skill inbox-review

# Chat mode
docker compose run --rm claude chat
```

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f obsidian-vault
docker compose logs -f gmail
```

### Health Checks

```bash
# Check all services
docker compose ps

# Individual health endpoints
curl http://localhost:4001/health  # obsidian-vault
curl http://localhost:4002/health  # gmail
curl http://localhost:4003/health  # calendar
```

## OAuth Management

### Adding Gmail Accounts

1. Start the Gmail service: `docker compose up -d gmail`
2. Visit http://localhost:4002/auth
3. Complete OAuth flow
4. Repeat for additional accounts

### Adding Calendar Accounts

1. Start the Calendar service: `docker compose up -d calendar`
2. Visit http://localhost:4003/auth
3. Complete OAuth flow

### Viewing Authenticated Accounts

- Gmail: http://localhost:4002/accounts
- Calendar: http://localhost:4003/accounts

## Multi-Account Setup

Both Gmail and Calendar support multiple Google accounts. Each service stores one token file per authenticated account.

### How Multi-Account Works

1. **Single OAuth App**: You create ONE OAuth app in Google Cloud Console
2. **Multiple Authentications**: Each account is authenticated separately via `/auth` endpoint
3. **Token Storage**: Tokens are stored in a Docker volume (one file per account)

### Adding Gmail Accounts

1. Start the Gmail service: `docker compose up -d gmail`
2. Visit http://localhost:4002/auth
3. Sign in with a Google account and authorize
4. Repeat steps 2-3 for each additional account
5. View all accounts: http://localhost:4002/accounts

### Adding Calendar Accounts

1. Start the Calendar service: `docker compose up -d calendar`
2. Visit http://localhost:4003/auth
3. Sign in with a Google account and authorize
4. Repeat for additional accounts

### Using Multiple Accounts

When using Gmail tools, specify which account:

- `list_accounts` - shows all authenticated accounts
- All other tools accept an `account` parameter (email address)

Calendar automatically aggregates events from all authenticated accounts.

## Production Deployment

For production, use the production compose override:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

This:

- Removes exposed ports (internal network only)
- Adds resource limits
- Enables restart policies
- Configures log rotation

## Security

### Container Isolation

- **Claude container**: Read-only vault access, can only interact via MCPs
- **MCP containers**: Limited filesystem access via bind mounts
- **Network**: Internal Docker network, no direct internet exposure

### Volume Permissions

| Volume         | Container       | Access         | Purpose                      |
| -------------- | --------------- | -------------- | ---------------------------- |
| Obsidian vault | claude          | read-only      | qmd search                   |
| Obsidian vault | obsidian-vault  | read-write     | Note operations (AI/ folder) |
| `assistant/`   | claude          | **read-write** | Self-modifying instructions  |
| qmd-index      | claude          | read-write     | Search index                 |
| OAuth tokens   | gmail, calendar | read-write     | Auth tokens                  |
| ~/.claude      | claude          | read-only      | Auth credentials only        |

### Self-Modifying Assistant

The `assistant/` folder is mounted **read-write**, allowing Claude to update its own:

- `CLAUDE.md` - Core instructions
- `.claude/skills/` - Skill definitions
- `.claude/settings.json` - Permissions
- `.mcp.json` - MCP configuration

This enables the assistant to learn and improve its workflows. Changes are persisted to your local filesystem and can be committed to version control.

**Security note**: The `.env` file and secrets are NOT exposed to the assistant.

### Secrets

- Never commit `.env` to version control
- Store OAuth credentials securely
- Consider using Docker secrets for production

## Troubleshooting

### Container won't start

```bash
# Check logs
docker compose logs obsidian-vault

# Rebuild images
docker compose build --no-cache
```

### OAuth issues

1. Ensure credentials file exists and is readable
2. Check token directory permissions
3. Re-authenticate: visit `/auth` endpoint

### MCP connection issues

```bash
# Check if MCP service is healthy
docker compose ps

# Test health endpoint
curl http://localhost:4001/health
```

### qmd not working

```bash
# Enter claude container
docker compose exec claude bash

# Check qmd installation
qmd --version

# Initialize index
qmd index /vault
```

## Updating

```bash
# Pull latest changes
git pull

# Rebuild images
docker compose build

# Restart services
docker compose up -d
```

## Uninstalling

```bash
# Stop and remove containers
docker compose down

# Remove volumes (WARNING: deletes OAuth tokens and qmd index)
docker compose down -v

# Remove images
docker compose down --rmi all
```
