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

interface LabelInfo {
  id: string;
  name: string;
  type: string;
}

// Store authenticated accounts
const accounts = new Map<string, AccountInfo>();

// Cache for labels per account (lazy loaded)
const labelCache = new Map<string, LabelInfo[]>();

// Load labels for an account (lazy, cached)
async function getLabelsForAccount(email: string): Promise<LabelInfo[]> {
  // Return cached labels if available
  if (labelCache.has(email)) {
    return labelCache.get(email)!;
  }

  // Fetch labels from API
  const gmail = getGmailClient(email);
  const response = await gmail.users.labels.list({
    userId: "me",
  });

  const labels = (response.data.labels || []).map((label) => ({
    id: label.id || "",
    name: label.name || "",
    type: label.type || "",
  }));

  // Cache the labels
  labelCache.set(email, labels);
  console.error(`Loaded ${labels.length} labels for account: ${email}`);

  return labels;
}

// Resolve label name to ID (supports nested labels like "AI/Done")
async function resolveLabelNameToId(
  email: string,
  labelName: string
): Promise<string> {
  // System labels are used as-is (uppercase)
  const systemLabels = [
    "INBOX",
    "UNREAD",
    "STARRED",
    "IMPORTANT",
    "SENT",
    "DRAFT",
    "SPAM",
    "TRASH",
    "CATEGORY_PERSONAL",
    "CATEGORY_SOCIAL",
    "CATEGORY_PROMOTIONS",
    "CATEGORY_UPDATES",
    "CATEGORY_FORUMS",
  ];

  if (systemLabels.includes(labelName.toUpperCase())) {
    return labelName.toUpperCase();
  }

  // For custom labels, look up by name
  const labels = await getLabelsForAccount(email);
  const label = labels.find(
    (l) => l.name.toLowerCase() === labelName.toLowerCase()
  );

  if (label) {
    return label.id;
  }

  // Label not found - throw error with helpful message
  throw new Error(
    `Label "${labelName}" not found. Available labels: ${labels
      .filter((l) => l.type === "user")
      .map((l) => l.name)
      .join(", ")}`
  );
}

// Resolve multiple label names to IDs
async function resolveLabelNamesToIds(
  email: string,
  labelNames: string[]
): Promise<string[]> {
  return Promise.all(
    labelNames.map((name) => resolveLabelNameToId(email, name))
  );
}

// AI processing labels - the assistant workflow convention for tracking which
// threads have been handled. AI/Done = fully processed; AI/Triage = the agent
// was unsure and left it for the user. Centralized here so the search filter and
// any future logic stay in sync.
const LABEL_DONE = "AI/Done";
const LABEL_TRIAGE = "AI/Triage";

// Deferred-email convention. A thread parked until a future "effective date"
// gets a dated nested label AI/Defer/YYYY-MM-DD (plus AI/Done, so it drops out
// of the daily "unprocessed" view). It resurfaces only via filter:"defer-due"
// once that date has arrived.
const LABEL_DEFER_PREFIX = "AI/Defer";
const DEFER_LABEL_RE = /^AI\/Defer\/(\d{4}-\d{2}-\d{2})$/;

// Archival markers. These two ordinary user buckets are the ONLY signal that a
// thread should leave INBOX: "Nieaktualne" = stale but worth keeping for
// reference, "Śmieci" = safe to delete (a marker only - we never delete). They
// are orthogonal and can be combined, and they layer on top of a category
// bucket (Zakupy, Finanse, ...). update_thread auto-removes INBOX whenever one
// of them ends up on the thread, and refuses to remove INBOX without one - so a
// plain category alone only tags a thread, leaving it in INBOX.
const LABEL_OUTDATED = "Nieaktualne";
const LABEL_JUNK = "Śmieci";

// Priority convention. Every classified incoming thread gets exactly one
// mutually-exclusive priority label P/0..P/3 (P/0 = critical, P/3 = noise).
// The MCP owns the disjointness: when update_thread sets a priority it adds the
// chosen P/<n> and strips any other P/* so two priorities can
// never coexist on a thread. The business meaning lives in the rulebooks; this
// layer only guarantees the mechanics.
const LABEL_PRIORITY_PREFIX = "P";
const PRIORITY_LABEL_RE = /^P\/([0-3])$/;

// Today's date as YYYY-MM-DD in the host's local timezone. Used to decide which
// deferred threads have "matured" (effective date <= today).
function todayISO(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

// Find a user label by name (case-insensitive); create it if missing. Gmail
// auto-creates the parent hierarchy for nested names like "AI/Defer/2026-06-18".
// This is the only path that creates labels - update_thread stays strict so a
// typo'd label name errors out instead of silently spawning junk labels.
async function ensureLabel(email: string, name: string): Promise<string> {
  const labels = await getLabelsForAccount(email);
  const existing = labels.find(
    (l) => l.name.toLowerCase() === name.toLowerCase()
  );
  if (existing) return existing.id;

  const gmail = getGmailClient(email);
  const created = await gmail.users.labels.create({
    userId: "me",
    requestBody: {
      name,
      labelListVisibility: "labelShow",
      messageListVisibility: "show",
    },
  });
  const info: LabelInfo = {
    id: created.data.id || "",
    name: created.data.name || name,
    type: created.data.type || "user",
  };
  labels.push(info); // keep the cached list in sync
  return info.id;
}

// All dated defer labels on the account, parsed into { id, name, date }.
async function deferLabelsWithDates(
  email: string
): Promise<{ id: string; name: string; date: string }[]> {
  const labels = await getLabelsForAccount(email);
  const out: { id: string; name: string; date: string }[] = [];
  for (const l of labels) {
    const m = l.name.match(DEFER_LABEL_RE);
    if (m) out.push({ id: l.id, name: l.name, date: m[1] });
  }
  return out;
}

// All priority labels (P/0..P/3) that already exist on the account,
// parsed into { id, name, level }. Used by update_thread to strip the other
// priorities when a new one is set (mutual exclusion).
async function priorityLabels(
  email: string
): Promise<{ id: string; name: string; level: string }[]> {
  const labels = await getLabelsForAccount(email);
  const out: { id: string; name: string; level: string }[] = [];
  for (const l of labels) {
    const m = l.name.match(PRIORITY_LABEL_RE);
    if (m) out.push({ id: l.id, name: l.name, level: m[1] });
  }
  return out;
}

// Resolve the label ops for setting a thread's priority: the id of the chosen
// P/<n> (created if missing) plus the ids of every OTHER existing
// P/* to strip, so the thread ends up with exactly one priority.
// Shared by update_thread and defer_thread - every path that marks a thread
// AI/Done also stamps it with a priority (the invariant: a processed thread is
// always filterable by importance).
async function priorityOps(
  email: string,
  priority: string
): Promise<{ name: string; addId: string; removeIds: string[] }> {
  if (!/^P[0-3]$/.test(priority)) {
    throw new Error(
      `Invalid priority "${priority}". Expected one of P0, P1, P2, P3.`
    );
  }
  // Agent-facing param stays P0..P3 for a stable interface; the label drops the
  // leading "P" so "P0" maps to "P/0".
  const name = `${LABEL_PRIORITY_PREFIX}/${priority.slice(1)}`;
  const addId = await ensureLabel(email, name);
  const removeIds = (await priorityLabels(email))
    .filter((l) => l.name !== name)
    .map((l) => l.id);
  return { name, addId, removeIds };
}

// Resolve the label ops for setting a thread's AI status. A processed thread
// carries exactly one status: AI/Done (handled) XOR AI/Triage (needs human).
// AI/Defer/* is the parked form of done and is owned solely by defer_thread, so
// setting a status via update_thread strips the opposite status AND any
// AI/Defer/* (a thread marked plain done/triage is no longer parked). The MCP
// owns this disjointness exactly like priorityOps owns the P/* one, so
// the agent never hand-toggles AI/Done vs AI/Triage. Done can still co-occur
// with defer (set together by defer_thread), but never with triage.
async function statusOps(
  email: string,
  status: string
): Promise<{ name: string; addId: string; removeIds: string[] }> {
  if (status !== "done" && status !== "triage") {
    throw new Error(`Invalid status "${status}". Expected 'done' or 'triage'.`);
  }
  const target = status === "done" ? LABEL_DONE : LABEL_TRIAGE;
  const other = status === "done" ? LABEL_TRIAGE : LABEL_DONE;
  const addId = await ensureLabel(email, target);
  const removeIds: string[] = [];
  try {
    removeIds.push(await resolveLabelNameToId(email, other));
  } catch {
    // opposite status label doesn't exist yet - nothing to strip
  }
  for (const l of await deferLabelsWithDates(email)) removeIds.push(l.id);
  return { name: target, addId, removeIds };
}

// Translate a high-level processing status into a Gmail search clause. This lets
// callers ask for a view ("unprocessed", "triage", ...) without hand-writing the
// -label: clauses, keeping the AI/Done|Triage convention owned by the MCP.
function filterClause(filter?: string): string {
  switch (filter) {
    case "unprocessed": // never touched: no Done, no Triage
      return `-label:${LABEL_DONE} -label:${LABEL_TRIAGE}`;
    case "triage": // the user's triage backlog
      return `label:${LABEL_TRIAGE}`;
    case "pending": // not finished (includes Triage)
      return `-label:${LABEL_DONE}`;
    case "done": // already processed
      return `label:${LABEL_DONE}`;
    default: // no status filter - raw query (backward compatible)
      return "";
  }
}

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
    description:
      "Search for email threads using Gmail search syntax. Filtering runs per-message under the hood (Gmail thread-level label negation is unreliable), then results are de-duplicated into threads. A thread is returned if ANY of its messages matches the query - so a new reply still surfaces its thread even when older messages carry labels you are excluding (e.g. -label:AI/Done). Threads are ordered by most recent matching message. Pass the optional 'filter' to restrict by AI processing status (the MCP appends the right AI/Done|AI/Triage clause) instead of writing -label: clauses yourself.",
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
            "Gmail search query (e.g., 'is:unread', 'from:example@gmail.com', 'subject:meeting'). Acts as the scope; combined with 'filter' if provided.",
        },
        filter: {
          type: "string",
          enum: ["unprocessed", "triage", "pending", "done", "defer-due"],
          description:
            "Optional AI processing status. 'unprocessed' = no AI/Done and no AI/Triage; 'triage' = has AI/Triage; 'pending' = no AI/Done (includes triage); 'done' = has AI/Done; 'defer-due' = threads deferred via defer_thread whose effective date (encoded in the AI/Defer/<date> label) is today or earlier - i.e. matured defers ready for re-evaluation. Omit for a raw query.",
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
    name: "update_thread",
    description:
      "Update a thread by adding/removing labels. Accepts label NAMES (not IDs) - e.g., 'Work/Projects', 'Newsletter'. System labels: INBOX, UNREAD, STARRED, IMPORTANT, CATEGORY_PERSONAL, CATEGORY_SOCIAL, CATEGORY_PROMOTIONS, CATEGORY_UPDATES, CATEGORY_FORUMS. STATUS: set the thread's AI status via the 'status' param (done|triage), NOT via addLabels/removeLabels - the MCP applies AI/Done XOR AI/Triage and strips the opposite plus any AI/Defer/*. Passing AI/Done, AI/Triage or AI/Defer/* in addLabels/removeLabels is rejected (use defer_thread for AI/Defer). Pass 'priority' to set a mutually-exclusive P/0..P/3 (the MCP swaps any existing priority for you). PRIORITY GUARD: if this call marks the thread AI/Done (status:'done'), a priority is required (pass 'priority' here, or the thread must already carry one) - every processed thread, incl. junk and sent mail, stays filterable by importance. ARCHIVING: the two archival markers 'Nieaktualne' (stale, keep for reference) and 'Śmieci' (safe to delete - a marker only, never deleted) are the ONLY way a thread leaves INBOX. Add one/both in addLabels and the MCP removes INBOX for you; they are orthogonal and combine, and layer on top of a category bucket (Zakupy, Finanse, ...). A plain category alone only tags the thread, leaving it in INBOX; removing INBOX without a marker is rejected.",
    inputSchema: {
      type: "object",
      properties: {
        account: {
          type: "string",
          description: "Email account",
        },
        threadId: {
          type: "string",
          description: "Thread ID to update",
        },
        addLabels: {
          type: "array",
          items: { type: "string" },
          description:
            "Label names to add to the thread (e.g., 'Newsletter', 'Zakupy'). Do NOT pass AI/Done, AI/Triage or AI/Defer/* here - use the 'status' param / defer_thread instead (rejected otherwise). Adding the archival marker 'Nieaktualne' and/or 'Śmieci' makes the MCP archive the thread (removes INBOX automatically).",
        },
        removeLabels: {
          type: "array",
          items: { type: "string" },
          description:
            "Label names to remove from the thread (e.g., 'INBOX', 'Newsletter'). Do NOT pass AI/Done, AI/Triage or AI/Defer/* here - the MCP swaps AI status for you via the 'status' param (rejected otherwise).",
        },
        status: {
          type: "string",
          enum: ["done", "triage"],
          description:
            "Thread AI status. 'done' applies AI/Done (processed); 'triage' applies AI/Triage (needs human, stays in INBOX). The MCP makes them mutually exclusive: it adds the chosen one and strips the opposite plus any AI/Defer/*. status:'done' triggers the PRIORITY GUARD (a priority is then required). This is the ONLY way to set AI/Done/AI/Triage.",
        },
        priority: {
          type: "string",
          enum: ["P0", "P1", "P2", "P3"],
          description:
            "Thread priority. The MCP applies P/<n> and removes any other P/* (disjointness guaranteed). REQUIRED whenever this call marks the thread AI/Done (status:'done') - including junk (Śmieci) and sent mail - unless the thread already carries a priority. P0 = critical/act today, P1 = high/days, P2 = normal/FYI, P3 = noise.",
        },
      },
      required: ["account", "threadId"],
    },
  },
  {
    name: "defer_thread",
    description:
      "Park a thread until an effective date. Adds the dated label AI/Defer/<until> plus AI/Done and the chosen P/<n> (so it leaves the daily 'unprocessed' view yet stays filterable by importance) and strips AI/Triage, any earlier defer date and any other priority. The thread resurfaces only via search_threads filter:'defer-due' once 'until' has arrived. Use for mail that is fine today but goes stale later (an event, a deadline, an offer's validity).",
    inputSchema: {
      type: "object",
      properties: {
        account: { type: "string", description: "Email account" },
        threadId: { type: "string", description: "Thread ID to defer" },
        until: {
          type: "string",
          description:
            "Effective date in YYYY-MM-DD (today or later). The thread re-surfaces via filter:'defer-due' on/after this date.",
        },
        priority: {
          type: "string",
          enum: ["P0", "P1", "P2", "P3"],
          description:
            "Required thread priority (P0 = critical … P3 = noise). A deferred thread is marked AI/Done, so it must carry a priority like every processed thread; it can be re-evaluated when the defer matures.",
        },
      },
      required: ["account", "threadId", "until", "priority"],
    },
  },
  {
    name: "cleanup_defer_labels",
    description:
      "Delete empty AI/Defer/<date> labels (housekeeping). Only dated defer labels with zero messages are removed; mail content is never touched. Run at the end of an inbox-processing session.",
    inputSchema: {
      type: "object",
      properties: {
        account: { type: "string", description: "Email account" },
      },
      required: ["account"],
    },
  },
  {
    name: "create_label",
    description:
      "Create a user label (if it doesn't exist) and return its ID. Supports nested names like 'AI/Defer' or 'Work/Projects' - Gmail auto-creates the parent hierarchy. Idempotent: if the label already exists, its existing ID is returned without error. This only creates the label - it does NOT apply it to any thread (use update_thread for that).",
    inputSchema: {
      type: "object",
      properties: {
        account: { type: "string", description: "Email account" },
        name: {
          type: "string",
          description: "Label name to create, e.g. 'Work/Faktury'",
        },
      },
      required: ["account", "name"],
    },
  },
  {
    name: "save_attachment",
    description:
      "Download an email attachment, save it to disk under .context/attachments and return its file path (NOT base64). The binary file never passes through the model context. Use get_message first to get the attachmentId; then move or read the saved file via the returned path.",
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
        const account = args?.account as string;
        const gmail = getGmailClient(account);
        const maxResults = (args?.maxResults as number) || 20;
        const filter = args?.filter as string | undefined;

        // Candidate thread IDs, de-duplicated, most-recent-matching first.
        const threadIds: string[] = [];
        const seen = new Set<string>();
        const MAX_PAGES = 5;

        if (filter === "defer-due") {
          // Deferred threads whose effective date has arrived (date <= today).
          // We query by labelId rather than a label: clause so the "/" in nested
          // label names needs no escaping. List each due label, merge threads.
          const today = todayISO();
          const due = (await deferLabelsWithDates(account)).filter(
            (l) => l.date <= today
          );
          const scope = (args?.query as string) || "";
          for (const label of due) {
            if (threadIds.length >= maxResults) break;
            let pageToken: string | undefined = undefined;
            for (
              let page = 0;
              page < MAX_PAGES && threadIds.length < maxResults;
              page++
            ) {
              const res: any = await gmail.users.messages.list({
                userId: "me",
                q: scope || undefined,
                labelIds: [label.id],
                maxResults: 100,
                pageToken,
              });
              for (const m of res.data.messages || []) {
                if (m.threadId && !seen.has(m.threadId)) {
                  seen.add(m.threadId);
                  threadIds.push(m.threadId);
                  if (threadIds.length >= maxResults) break;
                }
              }
              pageToken = res.data.nextPageToken || undefined;
              if (!pageToken) break;
            }
          }
        } else {
          // Combine the caller's scope query with the AI-status clause (if any).
          const clause = filterClause(filter);
          const q = [args?.query as string, clause].filter(Boolean).join(" ");

          // Filter per-message (Gmail thread-level label negation is unreliable
          // - a whole conversation disappears from -label:X once any message has
          // X, so new replies to processed threads would never resurface). We
          // list messages, then de-duplicate their threadIds. messages.list is
          // returned in reverse-chronological order, so first-seen order gives
          // threads sorted by most recent matching message. Page until we have
          // enough distinct threads (or hit a safety cap).
          let pageToken: string | undefined = undefined;
          for (
            let page = 0;
            page < MAX_PAGES && threadIds.length < maxResults;
            page++
          ) {
            const res: any = await gmail.users.messages.list({
              userId: "me",
              q,
              maxResults: 100,
              pageToken,
            });

            for (const m of res.data.messages || []) {
              if (m.threadId && !seen.has(m.threadId)) {
                seen.add(m.threadId);
                threadIds.push(m.threadId);
                if (threadIds.length >= maxResults) break;
              }
            }

            pageToken = res.data.nextPageToken || undefined;
            if (!pageToken) break;
          }
        }

        const threads = await Promise.all(
          threadIds.map(async (id) => {
            const threadData = await gmail.users.threads.get({
              userId: "me",
              id,
              format: "metadata",
              metadataHeaders: ["Subject", "From", "Date"],
            });

            const firstMessage = threadData.data.messages?.[0];
            const headers = firstMessage?.payload?.headers;

            return {
              id,
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
            labels: msg.labelIds,
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

      case "update_thread": {
        const account = args?.account as string;
        const gmail = getGmailClient(account);
        const threadId = args?.threadId as string;
        const addLabels = (args?.addLabels as string[]) || [];
        const removeLabels = (args?.removeLabels as string[]) || [];
        const priority = args?.priority as string | undefined;
        const status = args?.status as string | undefined;

        // AI status labels are owned by the MCP, not the caller: AI/Done and
        // AI/Triage are mutually exclusive and AI/Defer/* is set only by
        // defer_thread. Let them through addLabels/removeLabels and a caller
        // could leave a thread with both Done and Triage (or strip a defer by
        // hand). Reject them and point to the right knob instead.
        const isManagedAiLabel = (n: string) =>
          /^AI\/(Done|Triage|Defer)(\/|$)/i.test(n);
        const offending = [...addLabels, ...removeLabels].filter(
          isManagedAiLabel
        );
        if (offending.length > 0) {
          throw new Error(
            `Labels ${offending.join(
              ", "
            )} are managed by the MCP, not addLabels/removeLabels. Set AI/Done or AI/Triage via the 'status' param (done|triage); use defer_thread for AI/Defer. To archive a thread add the bucket 'Nieaktualne' and/or 'Śmieci' in addLabels - the MCP removes INBOX for you.`
          );
        }

        if (
          addLabels.length === 0 &&
          removeLabels.length === 0 &&
          !priority &&
          !status
        ) {
          return {
            content: [
              {
                type: "text",
                text: "No labels to add or remove",
              },
            ],
          };
        }

        // Resolve label names to IDs
        const addLabelIds =
          addLabels.length > 0
            ? await resolveLabelNamesToIds(account, addLabels)
            : [];
        const removeLabelIds =
          removeLabels.length > 0
            ? await resolveLabelNamesToIds(account, removeLabels)
            : [];

        // Priority: add the chosen P/<n> and strip every other
        // P/* so a thread carries exactly one priority at a time.
        let priorityName: string | undefined;
        if (priority) {
          const ops = await priorityOps(account, priority);
          priorityName = ops.name;
          if (!addLabelIds.includes(ops.addId)) addLabelIds.push(ops.addId);
          for (const id of ops.removeIds) {
            if (!removeLabelIds.includes(id)) removeLabelIds.push(id);
          }
        }

        // Status: add the chosen AI/Done|AI/Triage and strip the opposite plus
        // any AI/Defer/* so the thread carries exactly one AI status (defer is
        // re-applied only by defer_thread). Same shape as the priority block.
        let statusName: string | undefined;
        if (status) {
          const ops = await statusOps(account, status);
          statusName = ops.name;
          if (!addLabelIds.includes(ops.addId)) addLabelIds.push(ops.addId);
          for (const id of ops.removeIds) {
            if (!removeLabelIds.includes(id)) removeLabelIds.push(id);
          }
        }

        // Two guards fire only when we touch the thread's terminal state, so we
        // fetch its current labels just once and reason over the RESULTING set
        // (current ∪ added − removed):
        //   - archive guard: the two archival markers (Nieaktualne / Śmieci)
        //     are the ONLY thing that takes a thread out of INBOX. If the
        //     resulting set has one, the MCP removes INBOX for the caller; if
        //     the caller tries to remove INBOX without one, it's rejected (a
        //     plain category alone only tags, leaving the thread in INBOX).
        //   - priority guard: a thread that ends up AI/Done must carry a
        //     P/* - every processed thread is filterable by importance,
        //     incl. junk, outdated and sent mail.
        const isArchivalMarker = (n: string) =>
          n.toLowerCase() === LABEL_OUTDATED.toLowerCase() ||
          n.toLowerCase() === LABEL_JUNK.toLowerCase();
        const archiving = removeLabels.some((l) => l.toUpperCase() === "INBOX");
        const addingMarker = addLabels.some(isArchivalMarker);
        const addingDone = status === "done";
        if (archiving || addingDone || addingMarker) {
          const meta = await gmail.users.threads.get({
            userId: "me",
            id: threadId,
            format: "metadata",
          });
          const allLabels = await getLabelsForAccount(account);
          const idToName = new Map(allLabels.map((l) => [l.id, l.name]));
          const removeLower = new Set(removeLabels.map((l) => l.toLowerCase()));
          const resulting = new Set<string>();
          for (const msg of meta.data.messages || []) {
            for (const id of msg.labelIds || []) {
              const name = idToName.get(id) || id;
              if (!removeLower.has(name.toLowerCase())) resulting.add(name);
            }
          }
          for (const name of addLabels) {
            if (!removeLower.has(name.toLowerCase())) resulting.add(name);
          }
          if (priorityName) resulting.add(priorityName);
          if (statusName) resulting.add(statusName);

          const resultingHasMarker = [...resulting].some(isArchivalMarker);
          if (resultingHasMarker) {
            // A marker is present → archive: make sure INBOX is dropped.
            if (
              !removeLabelIds.some((id) => id.toUpperCase() === "INBOX")
            ) {
              removeLabelIds.push("INBOX");
            }
          } else if (archiving) {
            // Removing INBOX without a marker is not allowed - categories only
            // tag, they don't archive.
            throw new Error(
              `Archiving thread ${threadId} (removing INBOX) requires the archival marker '${LABEL_OUTDATED}' and/or '${LABEL_JUNK}' in addLabels. A plain category (e.g. Zakupy, Finanse, Newsletter) only tags the thread and leaves it in INBOX. Add 'Nieaktualne' (stale, keep for reference) and/or 'Śmieci' (safe to delete) to archive it.`
            );
          }

          const resultingDone = [...resulting].some(
            (n) => n.toLowerCase() === LABEL_DONE.toLowerCase()
          );
          const resultingPriority = [...resulting].some((n) =>
            PRIORITY_LABEL_RE.test(n)
          );
          if (resultingDone && !resultingPriority) {
            throw new Error(
              `Thread ${threadId} would be marked ${LABEL_DONE} without a priority. Every processed thread must carry a P/0..P/3 (incl. junk, outdated and sent mail) so it stays filterable by importance. Pass 'priority' (P0..P3) in this call.`
            );
          }
        }

        await gmail.users.threads.modify({
          userId: "me",
          id: threadId,
          requestBody: {
            addLabelIds: addLabelIds.length > 0 ? addLabelIds : undefined,
            removeLabelIds:
              removeLabelIds.length > 0 ? removeLabelIds : undefined,
          },
        });

        const changes: string[] = [];
        if (statusName) {
          changes.push(`status: ${statusName}`);
        }
        if (addLabels.length > 0) {
          changes.push(`added: ${addLabels.join(", ")}`);
        }
        if (priorityName) {
          changes.push(`priority: ${priorityName}`);
        }
        if (removeLabels.length > 0) {
          changes.push(`removed: ${removeLabels.join(", ")}`);
        }

        return {
          content: [
            {
              type: "text",
              text: `Updated thread ${threadId}: ${changes.join("; ")}`,
            },
          ],
        };
      }

      case "defer_thread": {
        const account = args?.account as string;
        const gmail = getGmailClient(account);
        const threadId = args?.threadId as string;
        const until = args?.until as string;
        const priority = args?.priority as string;

        if (!until || !/^\d{4}-\d{2}-\d{2}$/.test(until)) {
          throw new Error(
            `Invalid 'until' date "${until}". Expected YYYY-MM-DD.`
          );
        }
        if (until < todayISO()) {
          throw new Error(
            `'until' date ${until} is in the past (today is ${todayISO()}). Defer dates must be today or later.`
          );
        }
        if (!priority) {
          throw new Error(
            `defer_thread requires 'priority' (P0..P3). A deferred thread is marked ${LABEL_DONE}, so it must carry a priority like every processed thread.`
          );
        }

        // Add the dated defer label + AI/Done + the chosen priority; strip
        // AI/Triage, any other (stale) defer label and any other P/* so
        // the thread carries exactly one effective date and one priority.
        const deferName = `${LABEL_DEFER_PREFIX}/${until}`;
        const deferId = await ensureLabel(account, deferName);
        const doneId = await resolveLabelNameToId(account, LABEL_DONE);
        const prio = await priorityOps(account, priority);

        const others = (await deferLabelsWithDates(account))
          .filter((l) => l.name !== deferName)
          .map((l) => l.id);
        let triageId: string | undefined;
        try {
          triageId = await resolveLabelNameToId(account, LABEL_TRIAGE);
        } catch {
          triageId = undefined;
        }
        const removeLabelIds = [
          ...others,
          ...(triageId ? [triageId] : []),
          ...prio.removeIds,
        ];

        await gmail.users.threads.modify({
          userId: "me",
          id: threadId,
          requestBody: {
            addLabelIds: [deferId, doneId, prio.addId],
            removeLabelIds:
              removeLabelIds.length > 0 ? removeLabelIds : undefined,
          },
        });

        return {
          content: [
            {
              type: "text",
              text: `Deferred thread ${threadId} until ${until} (+${deferName}, +${LABEL_DONE}, ${prio.name}; resurfaces via filter:"defer-due" on/after ${until}).`,
            },
          ],
        };
      }

      case "cleanup_defer_labels": {
        const account = args?.account as string;
        const gmail = getGmailClient(account);

        // Delete empty AI/Defer/<date> labels (housekeeping only - scoped to
        // dated defer labels with zero messages; never touches mail content).
        const defers = await deferLabelsWithDates(account);
        const deleted: string[] = [];
        for (const label of defers) {
          const info: any = await gmail.users.labels.get({
            userId: "me",
            id: label.id,
          });
          if ((info.data.messagesTotal || 0) === 0) {
            await gmail.users.labels.delete({ userId: "me", id: label.id });
            deleted.push(label.name);
            // Drop it from the cached label list.
            const cached = labelCache.get(account);
            if (cached) {
              const idx = cached.findIndex((l) => l.id === label.id);
              if (idx >= 0) cached.splice(idx, 1);
            }
          }
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                { deleted, count: deleted.length },
                null,
                2
              ),
            },
          ],
        };
      }

      case "create_label": {
        const account = args?.account as string;
        const name = (args?.name as string)?.trim();
        if (!name) throw new Error("Label name is required");

        // Detect prior existence so the caller knows created vs. already-there.
        const existing = (await getLabelsForAccount(account)).find(
          (l) => l.name.toLowerCase() === name.toLowerCase()
        );
        // ensureLabel creates via the API and keeps labelCache in sync, so a
        // following update_thread/resolveLabelNameToId finds it without restart.
        const id = await ensureLabel(account, name);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ id, name, created: !existing }, null, 2),
            },
          ],
        };
      }

      case "save_attachment": {
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

        // Save the decoded file to disk and return its path - the binary
        // never goes through the model context (avoids huge base64 blobs).
        const ATT_DIR = process.env.GMAIL_ATTACHMENTS_DIR || "/attachments";
        const RET_BASE =
          process.env.GMAIL_ATTACHMENTS_RETURN_BASE || ".context/attachments";
        const rawName = attachmentInfo?.filename || "attachment";
        // Gmail filenames can contain slashes/illegal chars (e.g. "2025-FP/I/27707.pdf")
        const safeName = rawName.replace(/[\/\\:*?"<>|]/g, "_");
        const destDir = path.join(ATT_DIR, messageId);
        await fs.mkdir(destDir, { recursive: true });
        const buffer = Buffer.from(base64Data, "base64");
        await fs.writeFile(path.join(destDir, safeName), buffer);
        const returnedPath = path.join(RET_BASE, messageId, safeName);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  filename: safeName,
                  originalFilename: rawName,
                  mimeType:
                    attachmentInfo?.mimeType || "application/octet-stream",
                  size: attachment.data.size,
                  path: returnedPath,
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
