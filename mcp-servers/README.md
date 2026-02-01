# MCP Servers

Custom MCP (Model Context Protocol) servers for the Caracas AI Assistant.

## obsidian-vault

Permission-separated Obsidian vault access server.

### Features

- **Read any note** in the vault
- **Full write access** to `AI/` folder (assistant's workspace)
- **Append-only access** to user notes (outside `AI/`)
- **Path traversal protection** built-in

### Tools

| Tool | Description | Permissions |
|------|-------------|-------------|
| `read_note` | Read any note in vault | All notes |
| `list_notes` | List notes in a folder | All folders |
| `create_ai_note` | Create note in AI/ folder | AI/ only |
| `update_ai_note` | Update note in AI/ folder | AI/ only |
| `append_to_user_note` | Append to user notes | User notes only |
| `create_user_note` | Create new user note (no overwrite) | User folders only |

### Build

```bash
cd obsidian-vault
npm install
npm run build
```

### Configuration

Environment variables:
- `VAULT_PATH`: Path to Obsidian vault (required)
- `AI_NOTES_PREFIX`: Prefix for AI-writable folder (default: `AI/`)

## Gmail MCP Server (TODO)

The Gmail MCP server needs to be forked from [PaulFidika/gmail-mcp-server](https://github.com/PaulFidika/gmail-mcp-server) and modified to add:

1. Multi-account support
2. Label management tools (`apply_label`, `mark_important`, etc.)
3. Ensure send functionality is NOT implemented

This is a future enhancement - for now, use the base server or an alternative.
