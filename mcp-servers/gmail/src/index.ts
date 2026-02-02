#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
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
import TurndownService from "turndown";
import EmailReplyParser from "email-reply-parser";
import EmailForwardParser from "email-forward-parser";

// Configuration from environment
const CREDENTIALS_PATH = process.env.GMAIL_CREDENTIALS_PATH || "";
const TOKENS_PATH = process.env.GMAIL_TOKENS_PATH || "";
const MCP_TRANSPORT = process.env.MCP_TRANSPORT || "stdio";
const MCP_PORT = parseInt(process.env.MCP_PORT || "4002");

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
async function loadCredentials(): Promise<{
  client_id: string;
  client_secret: string;
  redirect_uris: string[];
}> {
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
        const email = file
          .replace(".json", "")
          .replace(/_/g, "@")
          .replace(/-/g, ".");
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
    throw new Error(
      `Account not found: ${email}. Available: ${[...accounts.keys()].join(
        ", "
      )}`
    );
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
          description:
            "Gmail search query (e.g., 'is:unread', 'from:example@gmail.com', 'subject:meeting')",
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
    description:
      "Get full details of a specific email message. Returns processed markdown with quotes/signatures stripped by default.",
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
        rawBody: {
          type: "boolean",
          description:
            "If true, return raw HTML/text without markdown conversion or quote stripping (default: false)",
        },
      },
      required: ["account", "messageId"],
    },
  },
  {
    name: "get_thread",
    description:
      "Get all messages in a thread. Returns processed markdown with quotes/signatures stripped by default.",
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
        rawBody: {
          type: "boolean",
          description:
            "If true, return raw HTML/text without markdown conversion or quote stripping (default: false)",
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
  {
    name: "get_attachment",
    description:
      "Get the content of an email attachment as base64-encoded data. Use get_message first to get the attachmentId.",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        messageId: {
          type: "string",
          description: "Message ID containing the attachment",
        },
        attachmentId: {
          type: "string",
          description: "Attachment ID from the message (from get_message response)",
        },
      },
      required: ["account", "messageId", "attachmentId"],
    },
  },
];

// Helper to decode base64url
function decodeBase64Url(data: string): string {
  const base64 = data.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(base64, "base64").toString("utf-8");
}

// Helper to encode message for sending
function encodeMessage(
  to: string,
  subject: string,
  body: string,
  cc?: string,
  bcc?: string,
  inReplyTo?: string
): string {
  const lines = [`To: ${to}`, `Subject: ${subject}`];

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
function getHeader(
  headers: gmail_v1.Schema$MessagePartHeader[] | undefined,
  name: string
): string {
  return (
    headers?.find((h) => h.name?.toLowerCase() === name.toLowerCase())?.value ||
    ""
  );
}

// ============================================================================
// Email Processing Functions
// ============================================================================

interface AttachmentInfo {
  attachmentId: string;
  filename: string;
  mimeType: string;
  size: number;
}

interface ProcessedEmail {
  body: string;
  attachments: AttachmentInfo[];
}

// Singleton Turndown instance for performance
let turndownInstance: TurndownService | null = null;

function getTurndownService(): TurndownService {
  if (!turndownInstance) {
    turndownInstance = new TurndownService({
      headingStyle: "atx",
      hr: "---",
      bulletListMarker: "-",
      codeBlockStyle: "fenced",
      fence: "```",
      emDelimiter: "*",
      strongDelimiter: "**",
      linkStyle: "inlined",
    });

    // Remove style, script, head, meta, link tags
    turndownInstance.remove(["style", "script", "head", "meta", "link"]);

    // Custom rule: Remove Gmail quote containers
    turndownInstance.addRule("gmail-quote", {
      filter: (node) => {
        if (node.nodeName !== "DIV") return false;
        const className = (node as Element).getAttribute("class") || "";
        return className.includes("gmail_quote");
      },
      replacement: () => "",
    });

    // Custom rule: Remove Outlook-style quoted content (blue border)
    turndownInstance.addRule("outlook-quote", {
      filter: (node) => {
        if (node.nodeName !== "DIV" && node.nodeName !== "BLOCKQUOTE") {
          return false;
        }
        const style = (node as Element).getAttribute("style") || "";
        return (
          style.includes("border-left") &&
          (style.includes("blue") ||
            style.includes("#00f") ||
            style.includes("rgb(0, 0, 255)") ||
            style.includes("#1010ff") ||
            style.includes("border:none"))
        );
      },
      replacement: () => "",
    });

    // Custom rule: Simplify images to [alt-text]
    turndownInstance.addRule("images", {
      filter: "img",
      replacement: (_content, node) => {
        const alt = (node as Element).getAttribute("alt") || "image";
        return `[${alt}]`;
      },
    });
  }
  return turndownInstance;
}

// Convert HTML to Markdown
function convertHtmlToMarkdown(html: string): string {
  if (!html || html.trim() === "") {
    return "";
  }

  try {
    const turndown = getTurndownService();
    let markdown = turndown.turndown(html);

    // Clean up excessive whitespace
    markdown = markdown
      .replace(/\n{3,}/g, "\n\n") // Max 2 consecutive newlines
      .replace(/^\s+|\s+$/g, ""); // Trim

    return markdown;
  } catch (error) {
    // Fallback: strip HTML tags
    console.error("HTML to markdown conversion failed:", error);
    return stripHtmlTags(html);
  }
}

// Fallback HTML tag stripping
function stripHtmlTags(html: string): string {
  return html
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

// Format file size for display
function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Process text content: handle forwards and strip replies/signatures
function processTextContent(text: string, subject: string): string {
  if (!text || text.trim() === "") {
    return "";
  }

  try {
    // Check if this is a forwarded email
    const forwardParser = new EmailForwardParser();
    const forwardResult = forwardParser.read(text, subject);

    if (forwardResult.forwarded && forwardResult.email) {
      // Format forwarded email nicely
      const forwardingMessage = forwardResult.message?.trim() || "";
      const originalEmail = forwardResult.email;

      let output = "";

      // Add the forwarding message (what the person wrote when forwarding)
      if (forwardingMessage) {
        output += forwardingMessage + "\n\n";
      }

      // Add formatted original email
      output += "---\n**Forwarded Email**\n";
      if (originalEmail.from?.address) {
        output += `From: ${originalEmail.from.name ? `${originalEmail.from.name} <${originalEmail.from.address}>` : originalEmail.from.address}\n`;
      }
      if (originalEmail.to) {
        // Handle both single object and array cases
        const toArray = Array.isArray(originalEmail.to)
          ? originalEmail.to
          : [originalEmail.to];
        const toAddresses = toArray
          .map((t) => (t.name ? `${t.name} <${t.address}>` : t.address))
          .join(", ");
        output += `To: ${toAddresses}\n`;
      }
      if (originalEmail.date) {
        output += `Date: ${originalEmail.date}\n`;
      }
      if (originalEmail.subject) {
        output += `Subject: ${originalEmail.subject}\n`;
      }
      output += "\n";

      // Process the original email body (strip its quotes/signatures too)
      if (originalEmail.body) {
        const replyParser = new EmailReplyParser();
        const parsed = replyParser.read(originalEmail.body);
        output += parsed.getVisibleText();
      }

      return output.trim();
    }

    // Not a forward - strip quoted replies and signatures
    const replyParser = new EmailReplyParser();
    const parsed = replyParser.read(text);
    return parsed.getVisibleText().trim();
  } catch (error) {
    console.error("Text processing failed:", error);
    return text; // Return original on error
  }
}

// Extract attachments from message payload
function extractAttachments(
  payload: gmail_v1.Schema$MessagePart
): AttachmentInfo[] {
  const attachments: AttachmentInfo[] = [];

  function scanParts(part: gmail_v1.Schema$MessagePart) {
    // Check if this part is an attachment (has filename and attachmentId)
    if (part.filename && part.filename.length > 0 && part.body?.attachmentId) {
      attachments.push({
        attachmentId: part.body.attachmentId,
        filename: part.filename,
        mimeType: part.mimeType || "application/octet-stream",
        size: part.body?.size || 0,
      });
    }

    // Recursively scan nested parts
    if (part.parts) {
      for (const subPart of part.parts) {
        scanParts(subPart);
      }
    }
  }

  scanParts(payload);
  return attachments;
}

// Extract raw body content (HTML preferred, fallback to text)
interface RawBodyContent {
  html: string | null;
  text: string | null;
}

function extractRawBody(payload: gmail_v1.Schema$MessagePart): RawBodyContent {
  let html: string | null = null;
  let text: string | null = null;

  function scanParts(part: gmail_v1.Schema$MessagePart) {
    // Direct body data
    if (part.body?.data) {
      const decoded = decodeBase64Url(part.body.data);
      if (part.mimeType === "text/html") {
        html = decoded;
      } else if (part.mimeType === "text/plain") {
        text = decoded;
      }
    }

    // Check nested parts
    if (part.parts) {
      for (const subPart of part.parts) {
        // Skip attachments
        if (subPart.filename && subPart.filename.length > 0) continue;
        scanParts(subPart);
      }
    }
  }

  scanParts(payload);
  return { html, text };
}

// Main email processing function
function processEmailContent(
  payload: gmail_v1.Schema$MessagePart,
  subject: string,
  rawMode: boolean = false
): ProcessedEmail {
  const attachments = extractAttachments(payload);
  const { html, text } = extractRawBody(payload);

  // If raw mode, return unprocessed content
  if (rawMode) {
    return {
      body: html || text || "",
      attachments,
    };
  }

  let processedBody = "";

  if (html) {
    // Convert HTML to markdown first
    const markdown = convertHtmlToMarkdown(html);
    // Then process for forwards/replies
    processedBody = processTextContent(markdown, subject);
  } else if (text) {
    // Process plain text directly
    processedBody = processTextContent(text, subject);
  }

  return {
    body: processedBody,
    attachments,
  };
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
        const rawBody = args?.rawBody === true;

        const message = await gmail.users.messages.get({
          userId: "me",
          id: args?.messageId as string,
          format: "full",
        });

        const headers = message.data.payload?.headers;
        const subject = getHeader(headers, "Subject");
        const { body, attachments } = processEmailContent(
          message.data.payload!,
          subject,
          rawBody
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  id: message.data.id,
                  threadId: message.data.threadId,
                  subject,
                  from: getHeader(headers, "From"),
                  to: getHeader(headers, "To"),
                  cc: getHeader(headers, "Cc"),
                  date: getHeader(headers, "Date"),
                  labels: message.data.labelIds,
                  snippet: message.data.snippet,
                  body,
                  attachments:
                    attachments.length > 0
                      ? attachments.map((a) => ({
                          attachmentId: a.attachmentId,
                          filename: a.filename,
                          mimeType: a.mimeType,
                          size: formatFileSize(a.size),
                          sizeBytes: a.size,
                        }))
                      : undefined,
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
        const rawBody = args?.rawBody === true;

        const thread = await gmail.users.threads.get({
          userId: "me",
          id: args?.threadId as string,
          format: "full",
        });

        const messages = (thread.data.messages || []).map((msg) => {
          const headers = msg.payload?.headers;
          const subject = getHeader(headers, "Subject");
          const { body, attachments } = processEmailContent(
            msg.payload!,
            subject,
            rawBody
          );

          return {
            id: msg.id,
            from: getHeader(headers, "From"),
            to: getHeader(headers, "To"),
            date: getHeader(headers, "Date"),
            subject,
            snippet: msg.snippet,
            body,
            attachments:
              attachments.length > 0
                ? attachments.map((a) => ({
                    attachmentId: a.attachmentId,
                    filename: a.filename,
                    mimeType: a.mimeType,
                    size: formatFileSize(a.size),
                    sizeBytes: a.size,
                  }))
                : undefined,
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

      case "get_attachment": {
        const gmail = getGmailClient(args?.account as string);
        const messageId = args?.messageId as string;
        const attachmentId = args?.attachmentId as string;

        // Fetch the attachment data
        const attachment = await gmail.users.messages.attachments.get({
          userId: "me",
          messageId: messageId,
          id: attachmentId,
        });

        // Get the message to find the attachment metadata
        const message = await gmail.users.messages.get({
          userId: "me",
          id: messageId,
          format: "full",
        });

        // Find the attachment info
        const attachments = extractAttachments(message.data.payload!);
        const attachmentInfo = attachments.find(
          (a) => a.attachmentId === attachmentId
        );

        // Convert from base64url to standard base64
        const base64Data = attachment.data.data
          ? attachment.data.data.replace(/-/g, "+").replace(/_/g, "/")
          : "";

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  filename: attachmentInfo?.filename || "attachment",
                  mimeType:
                    attachmentInfo?.mimeType || "application/octet-stream",
                  size: attachment.data.size,
                  data: base64Data,
                },
                null,
                2
              ),
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
function setupOAuthRoutes(
  app: express.Application,
  credentials: {
    client_id: string;
    client_secret: string;
    redirect_uris: string[];
  }
): void {
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
      res
        .status(500)
        .send("Authentication failed: " + (error as Error).message);
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
            ${
              accountList.length > 0
                ? accountList.map((a) => `<li>${a}</li>`).join("")
                : "<li>No accounts configured</li>"
            }
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

    // Create a single stateless transport
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined, // Stateless mode
    });

    // Connect server to transport once
    await server.connect(transport);

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
      console.error(`Gmail MCP server running on http://0.0.0.0:${MCP_PORT}`);
      console.error("Transport: Streamable HTTP (stateless)");
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
