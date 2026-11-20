# MCP Servers

Custom MCP (Model Context Protocol) servers for the Umbra AI Assistant.

## calendar

Google Calendar MCP server using [@nspady/google-calendar-mcp](https://github.com/nspady/google-calendar-mcp).

### Features

- **Multi-account support** via `manage-accounts` tool
- **List calendars** across all accounts
- **View and search events**
- **Create events** (with user permission)
- **Free/busy lookup**

### Enabled Tools

`list-calendars`, `list-events`, `get-event`, `search-events`, `list-colors`, `get-freebusy`, `get-current-time`, `create-event`, `manage-accounts`

### Configuration

Environment variables:

- `GOOGLE_OAUTH_CREDENTIALS`: Path to OAuth credentials JSON
- `GOOGLE_TOKEN_PATH`: Directory for account tokens
- `MCP_PORT`: Server port (default: 4003)
