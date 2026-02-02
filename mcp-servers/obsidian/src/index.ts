#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "fs/promises";
import * as path from "path";
import express, { Request, Response } from "express";

// Configuration from environment
const VAULT_PATH = process.env.VAULT_PATH || "";
const AI_NOTES_PREFIX = process.env.AI_NOTES_PREFIX || "AI/";
const MCP_TRANSPORT = process.env.MCP_TRANSPORT || "stdio";
const MCP_PORT = parseInt(process.env.MCP_PORT || "4001");

if (!VAULT_PATH) {
  console.error("Error: VAULT_PATH environment variable is required");
  process.exit(1);
}

// Security: Ensure path is within vault and normalized
function securePath(notePath: string): string {
  // Normalize and resolve the path
  const normalized = path.normalize(notePath).replace(/^\/+/, "");
  const fullPath = path.join(VAULT_PATH, normalized);
  const resolvedPath = path.resolve(fullPath);
  const resolvedVault = path.resolve(VAULT_PATH);

  // Check for path traversal
  if (!resolvedPath.startsWith(resolvedVault)) {
    throw new Error("Path traversal detected: access denied");
  }

  return resolvedPath;
}

// Check if a path is in the AI notes folder
function isAIPath(notePath: string): boolean {
  const normalized = path.normalize(notePath).replace(/^\/+/, "");
  return normalized.startsWith(AI_NOTES_PREFIX);
}

// Ensure path ends with .md
function ensureMarkdown(notePath: string): string {
  if (!notePath.endsWith(".md")) {
    return notePath + ".md";
  }
  return notePath;
}

// Tool definitions
const tools: Tool[] = [
  {
    name: "read_note",
    description:
      "Read the contents of any note in the Obsidian vault. Returns the full markdown content.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description:
            "Path to the note relative to vault root (e.g., 'Inbox/my-note.md' or 'AI/Memory/People.md')",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "list_notes",
    description:
      "List all notes in a folder within the Obsidian vault. Returns file paths and metadata.",
    inputSchema: {
      type: "object",
      properties: {
        folder: {
          type: "string",
          description:
            "Folder path relative to vault root (e.g., 'Inbox' or 'AI/Memory'). Empty string for vault root.",
        },
        recursive: {
          type: "boolean",
          description: "Whether to list notes in subfolders recursively",
        },
      },
      required: [],
    },
  },
  {
    name: "create_ai_note",
    description:
      "Create a new note in the AI/ folder. Only works for paths starting with 'AI/'. Used for assistant's working notes, research, drafts, and memory.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description:
            "Path for the new note, must start with 'AI/' (e.g., 'AI/Research/topic.md')",
        },
        content: {
          type: "string",
          description: "Markdown content for the note",
        },
      },
      required: ["path", "content"],
    },
  },
  {
    name: "update_ai_note",
    description:
      "Update an existing note in the AI/ folder. Only works for paths starting with 'AI/'. Replaces the entire content.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description:
            "Path to the note, must start with 'AI/' (e.g., 'AI/Memory/People.md')",
        },
        content: {
          type: "string",
          description: "New markdown content for the note",
        },
      },
      required: ["path", "content"],
    },
  },
  {
    name: "append_to_user_note",
    description:
      "Append content to the end of a user's note (outside AI/ folder). This is APPEND-ONLY - cannot modify existing content. Use sparingly and only when explicitly requested by the user.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description:
            "Path to the note (must NOT start with 'AI/', e.g., 'Inbox/ideas.md')",
        },
        content: {
          type: "string",
          description:
            "Content to append at the end of the note. Will be preceded by a newline.",
        },
      },
      required: ["path", "content"],
    },
  },
  {
    name: "create_user_note",
    description:
      "Create a new note in user folders (outside AI/). Use for creating new notes like daily dashboards. Cannot overwrite existing notes.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description:
            "Path for the new note (must NOT start with 'AI/', e.g., 'Inbox/Dashboard-2024-01-15.md')",
        },
        content: {
          type: "string",
          description: "Markdown content for the note",
        },
      },
      required: ["path", "content"],
    },
  },
  {
    name: "save_file",
    description:
      "Save a binary file (PDF, image, document) to the vault. Used for storing email attachments or downloaded files.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description:
            "Path for the file relative to vault root (e.g., 'Faktury/invoice-2025-01.pdf')",
        },
        data: {
          type: "string",
          description: "Base64-encoded file content",
        },
        overwrite: {
          type: "boolean",
          description: "Whether to overwrite if file exists (default: false)",
        },
      },
      required: ["path", "data"],
    },
  },
  {
    name: "list_files",
    description:
      "List non-markdown files in a folder. Useful for finding stored attachments.",
    inputSchema: {
      type: "object",
      properties: {
        folder: {
          type: "string",
          description:
            "Folder path relative to vault root. Empty string for vault root.",
        },
        recursive: {
          type: "boolean",
          description: "Whether to search recursively (default: false)",
        },
        extensions: {
          type: "array",
          items: { type: "string" },
          description:
            "Filter by extensions without dot (e.g., ['pdf', 'png']). Empty for all non-md files.",
        },
      },
    },
  },
];

// Create server
const server = new Server(
  {
    name: "obsidian",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List tools handler
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

// Tool execution handler
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "read_note": {
        const notePath = ensureMarkdown(args?.path as string);
        const fullPath = securePath(notePath);
        const content = await fs.readFile(fullPath, "utf-8");
        return {
          content: [{ type: "text", text: content }],
        };
      }

      case "list_notes": {
        const folder = (args?.folder as string) || "";
        const recursive = (args?.recursive as boolean) || false;
        const fullPath = securePath(folder || ".");

        const notes: Array<{ path: string; modified: string }> = [];

        async function scanDir(dir: string, prefix: string) {
          const entries = await fs.readdir(dir, { withFileTypes: true });
          for (const entry of entries) {
            const entryPath = path.join(dir, entry.name);
            const relativePath = prefix
              ? `${prefix}/${entry.name}`
              : entry.name;

            if (entry.isDirectory()) {
              // Skip hidden folders
              if (entry.name.startsWith(".")) continue;
              if (recursive) {
                await scanDir(entryPath, relativePath);
              }
            } else if (entry.name.endsWith(".md")) {
              const stat = await fs.stat(entryPath);
              notes.push({
                path: relativePath,
                modified: stat.mtime.toISOString(),
              });
            }
          }
        }

        await scanDir(fullPath, folder);

        // Sort by modification time, newest first
        notes.sort(
          (a, b) =>
            new Date(b.modified).getTime() - new Date(a.modified).getTime()
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(notes, null, 2),
            },
          ],
        };
      }

      case "create_ai_note": {
        const notePath = ensureMarkdown(args?.path as string);
        const content = args?.content as string;

        // Security: Only allow AI/ folder
        if (!isAIPath(notePath)) {
          throw new Error(
            `Permission denied: create_ai_note only works for paths starting with '${AI_NOTES_PREFIX}'. Got: ${notePath}`
          );
        }

        const fullPath = securePath(notePath);

        // Check if file already exists
        try {
          await fs.access(fullPath);
          throw new Error(
            `Note already exists at ${notePath}. Use update_ai_note to modify it.`
          );
        } catch (e) {
          if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
        }

        // Create directory if needed
        await fs.mkdir(path.dirname(fullPath), { recursive: true });

        // Write the file
        await fs.writeFile(fullPath, content, "utf-8");

        return {
          content: [{ type: "text", text: `Created note at ${notePath}` }],
        };
      }

      case "update_ai_note": {
        const notePath = ensureMarkdown(args?.path as string);
        const content = args?.content as string;

        // Security: Only allow AI/ folder
        if (!isAIPath(notePath)) {
          throw new Error(
            `Permission denied: update_ai_note only works for paths starting with '${AI_NOTES_PREFIX}'. Got: ${notePath}`
          );
        }

        const fullPath = securePath(notePath);

        // Check if file exists
        try {
          await fs.access(fullPath);
        } catch {
          throw new Error(
            `Note does not exist at ${notePath}. Use create_ai_note to create it.`
          );
        }

        // Write the file
        await fs.writeFile(fullPath, content, "utf-8");

        return {
          content: [{ type: "text", text: `Updated note at ${notePath}` }],
        };
      }

      case "append_to_user_note": {
        const notePath = ensureMarkdown(args?.path as string);
        const content = args?.content as string;

        // Security: NOT allowed in AI/ folder
        if (isAIPath(notePath)) {
          throw new Error(
            `Permission denied: append_to_user_note does not work for AI/ folder. Use update_ai_note instead.`
          );
        }

        const fullPath = securePath(notePath);

        // Check if file exists
        try {
          await fs.access(fullPath);
        } catch {
          throw new Error(
            `Note does not exist at ${notePath}. Cannot append to non-existent note.`
          );
        }

        // Append to the file
        await fs.appendFile(fullPath, "\n" + content, "utf-8");

        return {
          content: [{ type: "text", text: `Appended to note at ${notePath}` }],
        };
      }

      case "create_user_note": {
        const notePath = ensureMarkdown(args?.path as string);
        const content = args?.content as string;

        // Security: NOT allowed in AI/ folder
        if (isAIPath(notePath)) {
          throw new Error(
            `Permission denied: create_user_note does not work for AI/ folder. Use create_ai_note instead.`
          );
        }

        const fullPath = securePath(notePath);

        // Check if file already exists - cannot overwrite
        try {
          await fs.access(fullPath);
          throw new Error(
            `Note already exists at ${notePath}. Cannot overwrite user notes.`
          );
        } catch (e) {
          if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
        }

        // Create directory if needed
        await fs.mkdir(path.dirname(fullPath), { recursive: true });

        // Write the file
        await fs.writeFile(fullPath, content, "utf-8");

        return {
          content: [{ type: "text", text: `Created user note at ${notePath}` }],
        };
      }

      case "save_file": {
        const filePath = args?.path as string;
        const dataBase64 = args?.data as string;
        const overwrite = (args?.overwrite as boolean) || false;

        const fullPath = securePath(filePath);

        // Check if file already exists
        if (!overwrite) {
          try {
            await fs.access(fullPath);
            throw new Error(
              `File already exists at ${filePath}. Use overwrite: true to replace it.`
            );
          } catch (e) {
            if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
          }
        }

        // Decode base64 data
        const buffer = Buffer.from(dataBase64, "base64");

        // Create directory if needed
        await fs.mkdir(path.dirname(fullPath), { recursive: true });

        // Write the file
        await fs.writeFile(fullPath, buffer);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  status: "saved",
                  path: filePath,
                  size: buffer.length,
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case "list_files": {
        const folder = (args?.folder as string) || "";
        const recursive = (args?.recursive as boolean) || false;
        const extensions = (args?.extensions as string[]) || [];
        const fullPath = securePath(folder || ".");

        const files: Array<{ path: string; size: number; modified: string }> =
          [];

        async function scanDir(dir: string, prefix: string) {
          const entries = await fs.readdir(dir, { withFileTypes: true });
          for (const entry of entries) {
            const entryPath = path.join(dir, entry.name);
            const relativePath = prefix
              ? `${prefix}/${entry.name}`
              : entry.name;

            if (entry.isDirectory()) {
              // Skip hidden folders
              if (entry.name.startsWith(".")) continue;
              if (recursive) {
                await scanDir(entryPath, relativePath);
              }
            } else if (!entry.name.endsWith(".md")) {
              // Skip markdown files (those are handled by list_notes)
              // Also skip hidden files
              if (entry.name.startsWith(".")) continue;

              // Filter by extension if specified
              if (extensions.length > 0) {
                const ext = path.extname(entry.name).slice(1).toLowerCase();
                if (!extensions.includes(ext)) continue;
              }

              const stat = await fs.stat(entryPath);
              files.push({
                path: relativePath,
                size: stat.size,
                modified: stat.mtime.toISOString(),
              });
            }
          }
        }

        await scanDir(fullPath, folder);

        // Sort by modification time, newest first
        files.sort(
          (a, b) =>
            new Date(b.modified).getTime() - new Date(a.modified).getTime()
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(files, null, 2),
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [{ type: "text", text: `Error: ${message}` }],
      isError: true,
    };
  }
});

// Start server with appropriate transport
async function main() {
  if (MCP_TRANSPORT === "http") {
    // Streamable HTTP transport for Docker
    const app = express();

    // Create a single stateless transport
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined, // Stateless mode
    });

    // Connect server to transport once
    await server.connect(transport);

    // Health check endpoint
    app.get("/health", (_req: Request, res: Response) => {
      res.json({
        status: "ok",
        server: "obsidian-mcp",
        version: "1.0.0",
      });
    });

    // Handle all MCP requests
    app.all("/mcp", express.json(), async (req: Request, res: Response) => {
      try {
        await transport.handleRequest(req, res, req.body);
      } catch (error) {
        console.error("Error handling MCP request:", error);
        if (!res.headersSent) {
          res.status(500).json({ error: "Internal server error" });
        }
      }
    });

    app.listen(MCP_PORT, "0.0.0.0", () => {
      console.error(
        `Obsidian MCP server running on http://0.0.0.0:${MCP_PORT}`
      );
      console.error("Transport: Streamable HTTP (stateless)");
      console.error(`Vault path: ${VAULT_PATH}`);
    });
  } else {
    // stdio transport for local/CLI usage
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("Obsidian MCP server running (stdio transport)");
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
