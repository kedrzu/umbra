# MCP Servers

Custom MCP (Model Context Protocol) servers for the Umbra AI Assistant.

## obsidian

Permission-separated Obsidian vault access server.

### Features

- **Read any note** in the vault
- **Full write access** to `AI/` folder (assistant's workspace)
- **Append-only access** to user notes (outside `AI/`)
- **Path traversal protection** built-in

### Tools

| Tool                  | Description                         | Permissions       |
| --------------------- | ----------------------------------- | ----------------- |
| `read_note`           | Read any note in vault              | All notes         |
| `list_notes`          | List notes in a folder              | All folders       |
| `create_ai_note`      | Create note in AI/ folder           | AI/ only          |
| `update_ai_note`      | Update note in AI/ folder           | AI/ only          |
| `append_to_user_note` | Append to user notes                | User notes only   |
| `create_user_note`    | Create new user note (no overwrite) | User folders only |

### Build

```bash
cd obsidian
npm install
npm run build
```

### Configuration

Environment variables:

- `VAULT_PATH`: Path to Obsidian vault (required)
- `AI_NOTES_PREFIX`: Prefix for AI-writable folder (default: `AI/`)

## gmail

Multi-account Gmail MCP server with read-only access (no sending).

### Features

- **Multi-account support** - authenticate multiple Gmail accounts
- **Search and read** emails across all accounts
- **Create drafts** (no send capability for safety)
- **Label management** - apply labels, mark as read/important
- **OAuth management** - web-based authentication flow

### Tools

| Tool | Description |
|------|-------------|
| `list_accounts` | List all authenticated Gmail accounts |
| `search_threads` | Search emails with Gmail query syntax |
| `get_thread` | Get full thread with all messages |
| `get_message` | Get single message details |
| `create_draft` | Create email draft |
| `apply_label` | Apply label to messages |
| `mark_important` | Mark message as important |
| `mark_read` | Mark message as read |

### Multi-Account Usage

All tools (except `list_accounts`) require an `account` parameter specifying which Gmail account to use.

### Endpoints

- `GET /auth` - Start OAuth flow to add new account
- `GET /accounts` - List authenticated accounts
- `GET /health` - Health check

### Configuration

Environment variables:

- `GMAIL_CREDENTIALS_PATH`: Path to OAuth credentials JSON
- `GMAIL_TOKENS_PATH`: Directory for account tokens
- `MCP_PORT`: Server port (default: 4002)
- `MCP_TRANSPORT`: Transport type (`http` or `stdio`)

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
