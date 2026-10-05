// Local files for drafts (attachments and inline images).
//
// The server runs in a container that sees only the directories mounted into it
// (the umbra repo and the Obsidian vault, read-only, at their host paths). On top of
// that, every path is checked against an explicit allowlist after resolving symlinks,
// so a draft can never carry a file from outside those roots.

import * as fs from "fs/promises";
import * as path from "path";
import { detectMimeType } from "nodemailer/lib/mime-funcs/mime-types";
import type { RawAttachment } from "./compose.js";

// Gmail refuses to send anything bigger; checking up front beats a half-made draft.
export const MAX_ATTACHMENTS_BYTES = 25 * 1024 * 1024;

export interface FileAccess {
  baseDir: string; // relative paths resolve here (the repo root)
  roots: string[]; // files must live under one of these
}

// UMBRA_ROOT = repo root; GMAIL_FILE_ROOTS = allowed roots separated by '|'
// (the vault path contains spaces and colons are ambiguous, hence the pipe).
export function fileAccessFromEnv(env = process.env): FileAccess {
  const baseDir = env.UMBRA_ROOT || process.cwd();
  const roots = (env.GMAIL_FILE_ROOTS || baseDir)
    .split("|")
    .map((r) => r.trim())
    .filter(Boolean);
  return { baseDir, roots };
}

// Secrets living next to the allowed files: repo .env, OAuth credentials/tokens.
function isSecretFile(filePath: string): boolean {
  const name = path.basename(filePath).toLowerCase();
  return name.startsWith(".env") || /-(credentials|tokens)\.json$/.test(name);
}

function isInside(filePath: string, root: string): boolean {
  const rel = path.relative(root, filePath);
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

async function realRoots(roots: string[]): Promise<string[]> {
  const resolved = await Promise.all(
    roots.map((r) => fs.realpath(r).catch(() => null))
  );
  return resolved.filter((r): r is string => r !== null);
}

// Absolute path of a readable regular file inside the allowed roots, or an error.
export async function resolveLocalFile(
  input: string,
  access: FileAccess
): Promise<string> {
  const p = input.trim();
  if (!p) throw new Error("Empty file path");
  if (p.startsWith("~")) {
    throw new Error(`'${p}': use an absolute path instead of ~`);
  }

  const candidate = path.resolve(access.baseDir, p);
  let real: string;
  try {
    real = await fs.realpath(candidate);
  } catch {
    throw new Error(`File not found: ${p}`);
  }

  const roots = await realRoots(access.roots);
  if (!roots.some((root) => isInside(real, root))) {
    throw new Error(
      `'${p}' is outside the directories the Gmail server may read ` +
        `(${access.roots.join(", ")}). Copy the file into .context/outbox/ first.`
    );
  }
  if (isSecretFile(real)) {
    throw new Error(`'${p}' looks like a secrets file - refusing to attach it`);
  }
  const stat = await fs.stat(real);
  if (!stat.isFile()) throw new Error(`'${p}' is not a regular file`);
  return real;
}

export async function loadLocalFile(
  input: string,
  access: FileAccess
): Promise<RawAttachment> {
  const real = await resolveLocalFile(input, access);
  const filename = path.basename(real);
  return {
    filename,
    contentType: detectMimeType(filename),
    content: await fs.readFile(real),
  };
}

export function assertTotalSize(attachments: RawAttachment[]): void {
  const total = attachments.reduce((sum, a) => sum + a.content.length, 0);
  if (total > MAX_ATTACHMENTS_BYTES) {
    const mb = (n: number) => (n / 1024 / 1024).toFixed(1);
    throw new Error(
      `Attachments total ${mb(total)} MB - over Gmail's ${mb(MAX_ATTACHMENTS_BYTES)} MB limit. ` +
        "Share big files via a link instead."
    );
  }
}
