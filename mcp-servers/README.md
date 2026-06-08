# MCP Servers

Custom MCP (Model Context Protocol) servers for the Umbra AI Assistant.

## gmail

Multi-account Gmail MCP server with read-only access (no sending).

### Features

- **Multi-account support** - authenticate multiple Gmail accounts
- **Search and read** emails across all accounts
- **Create drafts** (no send capability for safety)
- **Label management** - unified `update_thread` for labels, archive, read/unread, star, important, categories
- **OAuth management** - web-based authentication flow

### Tools

| Tool             | Description                                                                 |
| ---------------- | --------------------------------------------------------------------------- |
| `list_accounts`  | List all authenticated Gmail accounts                                       |
| `search_threads` | Search emails with Gmail query syntax; omit `filter` for free-form search across all mail (incl. archived/processed) |
| `get_thread`     | Get full thread with all messages (label names included)                    |
| `get_message`    | Get single message details (label names included)                           |
| `create_draft`   | Create email draft                                                          |
| `list_labels`    | List all labels in an account                                               |
| `update_thread`  | Atomic thread changes in one call: AI status, defer (`deferUntil`), priority, labels (archive, categories, etc.) |
| `cleanup_defer_labels` | Delete empty `AI/Defer/<date>` labels (housekeeping)                  |
| `save_attachment`| Save attachment to disk (.context/attachments), return its path             |

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
