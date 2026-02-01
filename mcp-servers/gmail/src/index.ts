#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import express, { Request, Response } from "express";
import { google, gmail_v1 } from "googleapis";
import { OAuth2Client } from "google-auth-library";
import * as fs from "fs/promises";
import * as path from "path";

// Configuration from environment
const CREDENTIALS_PATH = process.env.GMAIL_CREDENTIALS_PATH || "";
const TOKENS_PATH = process.env.GMAIL_TOKENS_PATH || "";
const MCP_TRANSPORT = process.env.MCP_TRANSPORT || "stdio";
const MCP_PORT = parseInt(process.env.MCP_PORT || "3002");

// OAuth scopes - intentionally excludes send permission for safety
const SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.modify",
  "https://www.googleapis.com/auth/gmail.compose",
  "https://www.googleapis.com/auth/gmail.labels",
];

interface AccountInfo {
  email: string;
  oauth2Client: OAuth2Client;
  gmail: gmail_v1.Gmail;
}

// Store authenticated accounts
const accounts = new Map<string, AccountInfo>();

// Load credentials
async function loadCredentials(): Promise<{ client_id: string; client_secret: string; redirect_uris: string[] }> {
  if (!CREDENTIALS_PATH) {
    throw new Error("GMAIL_CREDENTIALS_PATH environment variable is required");
  }
  const content = await fs.readFile(CREDENTIALS_PATH, "utf-8");
  const credentials = JSON.parse(content);
  return credentials.installed || credentials.web;
}

// Load tokens for all accounts
async function loadTokens(): Promise<Map<string, unknown>> {
  if (!TOKENS_PATH) {
    return new Map();
  }

  try {
    const tokensDir = TOKENS_PATH;
    const files = await fs.readdir(tokensDir);
    const tokens = new Map<string, unknown>();

    for (const file of files) {
      if (file.endsWith(".json")) {
        const content = await fs.readFile(path.join(tokensDir, file), "utf-8");
        const token = JSON.parse(content);
        const email = file.replace(".json", "").replace(/_/g, "@").replace(/-/g, ".");
        tokens.set(email, token);
      }
    }

    return tokens;
  } catch {
    return new Map();
  }
}

// Save token for an account
async function saveToken(email: string, token: unknown): Promise<void> {
  if (!TOKENS_PATH) return;

  await fs.mkdir(TOKENS_PATH, { recursive: true });
  const filename = email.replace(/@/g, "_").replace(/\./g, "-") + ".json";
  await fs.writeFile(
    path.join(TOKENS_PATH, filename),
    JSON.stringify(token, null, 2)
  );
}

// Initialize accounts from saved tokens
async function initializeAccounts(): Promise<void> {
  const credentials = await loadCredentials();
  const tokens = await loadTokens();

  for (const [email, token] of tokens) {
    const oauth2Client = new google.auth.OAuth2(
      credentials.client_id,
      credentials.client_secret,
      credentials.redirect_uris[0]
    );

    oauth2Client.setCredentials(token as object);

    // Set up token refresh
    oauth2Client.on("tokens", async (newTokens) => {
      const currentToken = oauth2Client.credentials;
      const updatedToken = { ...currentToken, ...newTokens };
      await saveToken(email, updatedToken);
    });

    const gmail = google.gmail({ version: "v1", auth: oauth2Client });

    accounts.set(email, { email, oauth2Client, gmail });
    console.error(`Loaded account: ${email}`);
  }
}

// Get Gmail client for an account
function getGmailClient(email: string): gmail_v1.Gmail {
  const account = accounts.get(email);
  if (!account) {
    throw new Error(`Account not found: ${email}. Available: ${[...accounts.keys()].join(", ")}`);
  }
  return account.gmail;
}

// Tool definitions
const tools: Tool[] = [
  {
    name: "list_accounts",
    description: "List all authenticated Gmail accounts",
    inputSchema: {
      type: "object",
      properties: {},
      required: [],
    },
  },
  {
    name: "search_threads",
    description: "Search for email threads using Gmail search syntax",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account to search in",
        },
        query: {
          type: "string",
          description: "Gmail search query (e.g., 'is:unread', 'from:example@gmail.com', 'subject:meeting')",
        },
        maxResults: {
          type: "number",
          description: "Maximum number of threads to return (default: 20)",
        },
      },
      required: ["account", "query"],
    },
  },
  {
    name: "get_message",
    description: "Get full details of a specific email message",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "The ID of the message to retrieve",
        },
      },
      required: ["account", "messageId"],
    },
  },
  {
    name: "get_thread",
    description: "Get all messages in a thread",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        threadId: {
          type: "string",
          description: "The ID of the thread to retrieve",
        },
      },
      required: ["account", "threadId"],
    },
  },
  {
    name: "create_draft",
    description: "Create a draft email (does NOT send)",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account to create draft in",
        },
        to: {
          type: "string",
          description: "Recipient email address(es), comma-separated",
        },
        subject: {
          type: "string",
          description: "Email subject",
        },
        body: {
          type: "string",
          description: "Email body (plain text or HTML)",
        },
        cc: {
          type: "string",
          description: "CC recipients, comma-separated",
        },
        bcc: {
          type: "string",
          description: "BCC recipients, comma-separated",
        },
        threadId: {
          type: "string",
          description: "Thread ID to reply to (optional)",
        },
        inReplyTo: {
          type: "string",
          description: "Message-ID to reply to (optional)",
        },
      },
      required: ["account", "to", "subject", "body"],
    },
  },
  {
    name: "list_labels",
    description: "List all labels in an account",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
      },
      required: ["account"],
    },
  },
  {
    name: "apply_label",
    description: "Apply a label to a message",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "Message ID to label",
        },
        labelId: {
          type: "string",
          description: "Label ID to apply",
        },
      },
      required: ["account", "messageId", "labelId"],
    },
  },
  {
    name: "remove_label",
    description: "Remove a label from a message",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "Message ID",
        },
        labelId: {
          type: "string",
          description: "Label ID to remove",
        },
      },
      required: ["account", "messageId", "labelId"],
    },
  },
  {
    name: "mark_read",
    description: "Mark a message as read",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "Message ID to mark as read",
        },
      },
      required: ["account", "messageId"],
    },
  },
  {
    name: "mark_unread",
    description: "Mark a message as unread",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "Message ID to mark as unread",
        },
      },
      required: ["account", "messageId"],
    },
  },
  {
    name: "mark_important",
    description: "Mark a message as important",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "Message ID to mark as important",
        },
      },
      required: ["account", "messageId"],
    },
  },
];

// Helper to decode base64url
function decodeBase64Url(data: string): string {
  const base64 = data.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(base64, "base64").toString("utf-8");
}

// Helper to encode message for sending
function encodeMessage(to: string, subject: string, body: string, cc?: string, bcc?: string, inReplyTo?: string): string {
  const lines = [
    `To: ${to}`,
    `Subject: ${subject}`,
  ];

  if (cc) lines.push(`Cc: ${cc}`);
  if (bcc) lines.push(`Bcc: ${bcc}`);
  if (inReplyTo) lines.push(`In-Reply-To: ${inReplyTo}`);

  lines.push("Content-Type: text/html; charset=utf-8");
  lines.push("");
  lines.push(body);

  const message = lines.join("\r\n");
  return Buffer.from(message).toString("base64url");
}

// Extract message parts
function extractMessageBody(payload: gmail_v1.Schema$MessagePart): string {
  if (payload.body?.data) {
    return decodeBase64Url(payload.body.data);
  }

  if (payload.parts) {
    // Prefer HTML, fallback to plain text
    const htmlPart = payload.parts.find((p) => p.mimeType === "text/html");
    if (htmlPart?.body?.data) {
      return decodeBase64Url(htmlPart.body.data);
    }

    const textPart = payload.parts.find((p) => p.mimeType === "text/plain");
    if (textPart?.body?.data) {
      return decodeBase64Url(textPart.body.data);
    }

    // Recursive check for nested parts
    for (const part of payload.parts) {
      if (part.parts) {
        const nested = extractMessageBody(part);
        if (nested) return nested;
      }
    }
  }

  return "";
}

// Get header value
function getHeader(headers: gmail_v1.Schema$MessagePartHeader[] | undefined, name: string): string {
  return headers?.find((h) => h.name?.toLowerCase() === name.toLowerCase())?.value || "";
}

// Create server
const server = new Server(
  {
    name: "gmail",
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
      case "list_accounts": {
        const accountList = [...accounts.keys()];
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ accounts: accountList }, null, 2),
            },
          ],
        };
      }

      case "search_threads": {
        const gmail = getGmailClient(args?.account as string);
        const maxResults = (args?.maxResults as number) || 20;

        const response = await gmail.users.threads.list({
          userId: "me",
          q: args?.query as string,
          maxResults,
        });

        const threads = await Promise.all(
          (response.data.threads || []).map(async (thread) => {
            const threadData = await gmail.users.threads.get({
              userId: "me",
              id: thread.id!,
              format: "metadata",
              metadataHeaders: ["Subject", "From", "Date"],
            });

            const firstMessage = threadData.data.messages?.[0];
            const headers = firstMessage?.payload?.headers;

            return {
              id: thread.id,
              snippet: threadData.data.messages?.[0]?.snippet,
              subject: getHeader(headers, "Subject"),
              from: getHeader(headers, "From"),
              date: getHeader(headers, "Date"),
              messageCount: threadData.data.messages?.length,
            };
          })
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ threads, count: threads.length }, null, 2),
            },
          ],
        };
      }

      case "get_message": {
        const gmail = getGmailClient(args?.account as string);

        const message = await gmail.users.messages.get({
          userId: "me",
          id: args?.messageId as string,
          format: "full",
        });

        const headers = message.data.payload?.headers;
        const body = extractMessageBody(message.data.payload!);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  id: message.data.id,
                  threadId: message.data.threadId,
                  subject: getHeader(headers, "Subject"),
                  from: getHeader(headers, "From"),
                  to: getHeader(headers, "To"),
                  cc: getHeader(headers, "Cc"),
                  date: getHeader(headers, "Date"),
                  labels: message.data.labelIds,
                  snippet: message.data.snippet,
                  body,
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case "get_thread": {
        const gmail = getGmailClient(args?.account as string);

        const thread = await gmail.users.threads.get({
          userId: "me",
          id: args?.threadId as string,
          format: "full",
        });

        const messages = (thread.data.messages || []).map((msg) => {
          const headers = msg.payload?.headers;
          return {
            id: msg.id,
            from: getHeader(headers, "From"),
            to: getHeader(headers, "To"),
            date: getHeader(headers, "Date"),
            subject: getHeader(headers, "Subject"),
            snippet: msg.snippet,
            body: extractMessageBody(msg.payload!),
          };
        });

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  threadId: thread.data.id,
                  messageCount: messages.length,
                  messages,
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case "create_draft": {
        const gmail = getGmailClient(args?.account as string);

        const raw = encodeMessage(
          args?.to as string,
          args?.subject as string,
          args?.body as string,
          args?.cc as string,
          args?.bcc as string,
          args?.inReplyTo as string
        );

        const draft = await gmail.users.drafts.create({
          userId: "me",
          requestBody: {
            message: {
              raw,
              threadId: args?.threadId as string,
            },
          },
        });

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  status: "Draft created",
                  draftId: draft.data.id,
                  messageId: draft.data.message?.id,
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case "list_labels": {
        const gmail = getGmailClient(args?.account as string);

        const response = await gmail.users.labels.list({
          userId: "me",
        });

        const labels = (response.data.labels || []).map((label) => ({
          id: label.id,
          name: label.name,
          type: label.type,
        }));

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ labels }, null, 2),
            },
          ],
        };
      }

      case "apply_label": {
        const gmail = getGmailClient(args?.account as string);

        await gmail.users.messages.modify({
          userId: "me",
          id: args?.messageId as string,
          requestBody: {
            addLabelIds: [args?.labelId as string],
          },
        });

        return {
          content: [
            {
              type: "text",
              text: `Applied label ${args?.labelId} to message ${args?.messageId}`,
            },
          ],
        };
      }

      case "remove_label": {
        const gmail = getGmailClient(args?.account as string);

        await gmail.users.messages.modify({
          userId: "me",
          id: args?.messageId as string,
          requestBody: {
            removeLabelIds: [args?.labelId as string],
          },
        });

        return {
          content: [
            {
              type: "text",
              text: `Removed label ${args?.labelId} from message ${args?.messageId}`,
            },
          ],
        };
      }

      case "mark_read": {
        const gmail = getGmailClient(args?.account as string);

        await gmail.users.messages.modify({
          userId: "me",
          id: args?.messageId as string,
          requestBody: {
            removeLabelIds: ["UNREAD"],
          },
        });

        return {
          content: [
            {
              type: "text",
              text: `Marked message ${args?.messageId} as read`,
            },
          ],
        };
      }

      case "mark_unread": {
        const gmail = getGmailClient(args?.account as string);

        await gmail.users.messages.modify({
          userId: "me",
          id: args?.messageId as string,
          requestBody: {
            addLabelIds: ["UNREAD"],
          },
        });

        return {
          content: [
            {
              type: "text",
              text: `Marked message ${args?.messageId} as unread`,
            },
          ],
        };
      }

      case "mark_important": {
        const gmail = getGmailClient(args?.account as string);

        await gmail.users.messages.modify({
          userId: "me",
          id: args?.messageId as string,
          requestBody: {
            addLabelIds: ["IMPORTANT"],
          },
        });

        return {
          content: [
            {
              type: "text",
              text: `Marked message ${args?.messageId} as important`,
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

// OAuth routes for authentication
function setupOAuthRoutes(app: express.Application, credentials: { client_id: string; client_secret: string; redirect_uris: string[] }): void {
  // Start OAuth flow
  app.get("/auth", (req: Request, res: Response) => {
    const oauth2Client = new google.auth.OAuth2(
      credentials.client_id,
      credentials.client_secret,
      `http://localhost:${MCP_PORT}/oauth2callback`
    );

    const url = oauth2Client.generateAuthUrl({
      access_type: "offline",
      scope: SCOPES,
      prompt: "consent",
    });

    res.redirect(url);
  });

  // OAuth callback
  app.get("/oauth2callback", async (req: Request, res: Response) => {
    const code = req.query.code as string;

    if (!code) {
      res.status(400).send("No authorization code provided");
      return;
    }

    try {
      const oauth2Client = new google.auth.OAuth2(
        credentials.client_id,
        credentials.client_secret,
        `http://localhost:${MCP_PORT}/oauth2callback`
      );

      const { tokens } = await oauth2Client.getToken(code);
      oauth2Client.setCredentials(tokens);

      // Get user email
      const gmail = google.gmail({ version: "v1", auth: oauth2Client });
      const profile = await gmail.users.getProfile({ userId: "me" });
      const email = profile.data.emailAddress!;

      // Save token
      await saveToken(email, tokens);

      // Add to accounts
      oauth2Client.on("tokens", async (newTokens) => {
        const currentToken = oauth2Client.credentials;
        const updatedToken = { ...currentToken, ...newTokens };
        await saveToken(email, updatedToken);
      });

      accounts.set(email, { email, oauth2Client, gmail });

      res.send(`
        <html>
          <body>
            <h1>Authentication Successful!</h1>
            <p>Account <strong>${email}</strong> has been added.</p>
            <p>You can close this window.</p>
            <p><a href="/auth">Add another account</a></p>
          </body>
        </html>
      `);
    } catch (error) {
      console.error("OAuth error:", error);
      res.status(500).send("Authentication failed: " + (error as Error).message);
    }
  });

  // List accounts page
  app.get("/accounts", (_req: Request, res: Response) => {
    const accountList = [...accounts.keys()];
    res.send(`
      <html>
        <body>
          <h1>Gmail MCP - Accounts</h1>
          <h2>Authenticated Accounts:</h2>
          <ul>
            ${accountList.length > 0 ? accountList.map((a) => `<li>${a}</li>`).join("") : "<li>No accounts configured</li>"}
          </ul>
          <p><a href="/auth">Add account</a></p>
        </body>
      </html>
    `);
  });
}

// Start server
async function main() {
  // Initialize accounts
  await initializeAccounts();

  if (MCP_TRANSPORT === "http") {
    const credentials = await loadCredentials();
    const app = express();

    // Health check
    app.get("/health", (_req: Request, res: Response) => {
      res.json({
        status: "ok",
        server: "gmail-mcp",
        version: "1.0.0",
        accounts: [...accounts.keys()],
      });
    });

    // OAuth routes
    setupOAuthRoutes(app, credentials);

    // Store active transports
    const transports = new Map<string, SSEServerTransport>();

    // SSE endpoint
    app.get("/sse", async (req: Request, res: Response) => {
      console.error("New SSE connection");

      const transport = new SSEServerTransport("/messages", res);
      const sessionId = crypto.randomUUID();
      transports.set(sessionId, transport);

      res.on("close", () => {
        console.error(`SSE connection closed: ${sessionId}`);
        transports.delete(sessionId);
      });

      await server.connect(transport);
    });

    // Messages endpoint
    app.post("/messages", express.json(), async (req: Request, res: Response) => {
      const sessionId = req.query.sessionId as string;
      const transport = transports.get(sessionId);

      if (!transport) {
        res.status(400).json({ error: "No active session" });
        return;
      }

      try {
        await transport.handlePostMessage(req, res);
      } catch (error) {
        console.error("Error handling message:", error);
        res.status(500).json({ error: "Internal server error" });
      }
    });

    app.listen(MCP_PORT, "0.0.0.0", () => {
      console.error(`Gmail MCP server running on http://0.0.0.0:${MCP_PORT}`);
      console.error("Transport: HTTP/SSE");
      console.error(`Accounts loaded: ${accounts.size}`);
      console.error(`Visit http://localhost:${MCP_PORT}/auth to add accounts`);
    });
  } else {
    // stdio transport
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("Gmail MCP server running (stdio transport)");
    console.error(`Accounts loaded: ${accounts.size}`);
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
