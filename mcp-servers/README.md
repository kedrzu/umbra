# MCP Servers

Custom MCP (Model Context Protocol) servers for the Umbra AI Assistant.

## gmail

Multi-account Gmail MCP server with read-only access (no sending).

### Features

- **Multi-account support** - authenticate multiple Gmail accounts
- **Search and read** emails across all accounts
- **Create and edit drafts** (no send capability for safety) - body written in Markdown, rendered to
  Gmail-looking HTML + a plain-text part; the account's Gmail signature is appended and replies
  (`threadId`) get Gmail-style quoting and `In-Reply-To`/`References` automatically
- **Files in drafts** - `attachments: [paths]` attaches files; a local image in the body
  (`![alt](/abs/path.png)`, `![alt](<path with spaces.png>)`) is embedded inline (`cid:`)
- **Label management** - unified `update_thread` for labels, archive, read/unread, star, important, categories
- **OAuth management** - web-based authentication flow

### Tools

| Tool             | Description                                                                 |
| ---------------- | --------------------------------------------------------------------------- |
| `list_accounts`  | List all authenticated Gmail accounts                                       |
| `search_threads` | Search emails with Gmail query syntax; omit `filter` for free-form search across all mail (incl. archived/processed) |
| `get_thread`     | Get full thread with all messages (label names included)                    |
| `get_message`    | Get single message details (label names included)                           |
| `create_draft`   | Create email draft from Markdown (signature + reply quote added by the server); `attachments`, inline images |
| `list_drafts`    | List drafts (optionally by `threadId` or Gmail query)                       |
| `get_draft`      | Get a draft; body as Markdown without signature/quote, inline images as `![alt](cid:…)` |
| `update_draft`   | Edit a draft in place (same `draftId`); only given fields change; `attachments` adds, `removeAttachments` drops by filename |
| `discard_draft`  | Discard a draft: moves it to Trash (recoverable 30 days), never `drafts.delete` (permanent); refuses non-drafts |
| `list_labels`    | List all labels in an account                                               |
| `update_thread`  | Atomic thread changes in one call: AI status, priority, labels (archive, categories, etc.) |
| `cleanup_labels` | Delete user labels by prefix (housekeeping; empty-only by default, mail untouched)    |
| `save_attachment`| Save attachment to disk (.context/attachments), return its path             |

### Files in drafts

- **Where from**: the container mounts the repo and the Obsidian vault **read-only at their host
  paths**, so `/Users/...` paths and the `obsidian/` symlink resolve unchanged. Relative paths
  resolve against the repo root (`.context/attachments/...` from `save_attachment` works as is).
  Anything outside `GMAIL_FILE_ROOTS` (after resolving symlinks), `.env*` and
  `*-credentials.json`/`*-tokens.json` is refused. Scratch files: `.context/outbox/`
  (the agent's `$TMPDIR` is not visible to the container).
- **Inline images**: only images in the content are embedded (signature and quote keep theirs);
  `http(s):`, `data:` and `cid:` sources are left alone. The plain-text part shows
  `[obraz: alt]` instead of a local path. One file used twice is attached once.
- **Gmail's own MIME format is mandatory**: `mixed > related > (alternative, images)`, each image
  with `Content-ID: <ii_…>` + `X-Attachment-Id: ii_…`, disposition `attachment`. Drafts are sent
  from the Gmail web UI, whose composer re-embeds only images it recognises as its own; any other
  `cid:` (e.g. nodemailer's default layout) becomes a dead `mail.google.com/...view=fimg` link in the
  sent mail, visible to nobody. A part counts as inline when the HTML references its `cid:`.
- **Round trip**: `get_draft` returns inline images as `![alt](cid:…)`; `update_draft` keeps an old
  inline image as long as the new body still references its `cid:`. Regular attachments survive
  every update.
- **Limits**: 25 MB in total (checked before any API call); drafts are uploaded as
  `message/rfc822` media, so multi-MB files are fine.

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
- `UMBRA_ROOT`: Repo root; relative draft file paths resolve here (`.env`, mounted at the same path)
- `GMAIL_FILE_ROOTS`: `|`-separated directories drafts may read files from (set by `docker-compose.yml`)

### Development

Draft rendering (`src/compose.ts`) and the file access policy (`src/files.ts`) are unit-tested: `npm test`. After changes rebuild the
container: `docker compose up -d --build gmail` (tokens live in a volume and survive the rebuild).

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
