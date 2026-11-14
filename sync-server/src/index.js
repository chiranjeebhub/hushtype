// Hushtype sync server. Stores one encrypted blob per group of paired devices and hands it back.
// It never sees the pairing secret, so it can't read anyone's dictionary. See README.md.

export const MAX_BLOB_BYTES = 512 * 1024;
const GROUP_PATH = /^\/v1\/groups\/([0-9a-f]{32})$/;
const TOKEN = /^Bearer ([A-Za-z0-9_-]{43})$/;

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      console.error(error);
      return text(500, "Server error");
    }
  },
};

async function handle(request, env) {
  const url = new URL(request.url);
  if (url.pathname === "/" && request.method === "GET") {
    return text(200, "Hushtype sync server");
  }
  const match = GROUP_PATH.exec(url.pathname);
  if (!match) return text(404, "Not found");
  const id = match[1];

  const token = TOKEN.exec(request.headers.get("Authorization") ?? "");
  if (!token) return text(401, "Missing token");
  const authHash = await sha256Hex(token[1]);

  switch (request.method) {
    case "GET":
      return get(env.DB, id, authHash);
    case "PUT":
      return put(env.DB, id, authHash, request);
    default:
      return text(405, "Method not allowed");
  }
}

async function get(db, id, authHash) {
  const row = await db.prepare("SELECT auth_hash, version, blob FROM groups WHERE id = ?").bind(id).first();
  if (!row) return text(404, "No such group");
  if (row.auth_hash !== authHash) return text(401, "Wrong token");
  return new Response(fromBase64(row.blob), {
    status: 200,
    headers: { "Content-Type": "application/octet-stream", ETag: etag(row.version), "Cache-Control": "no-store" },
  });
}

async function put(db, id, authHash, request) {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (declared > MAX_BLOB_BYTES) return text(413, "Too large");
  const body = new Uint8Array(await request.arrayBuffer());
  if (body.length > MAX_BLOB_BYTES) return text(413, "Too large");
  if (body.length < 30 || body[0] !== 1) return text(400, "Not a Hushtype blob");
  const blob = toBase64(body);
  const now = Date.now();

  const ifNoneMatch = request.headers.get("If-None-Match");
  const ifMatch = request.headers.get("If-Match");
  if (ifNoneMatch === "*") {
    const result = await db
      .prepare(
        "INSERT INTO groups (id, auth_hash, version, blob, updated_at) VALUES (?, ?, 1, ?, ?) ON CONFLICT(id) DO NOTHING",
      )
      .bind(id, authHash, blob, now)
      .run();
    if (result.meta.changes === 0) return conflictOrUnauthorized(db, id, authHash);
    return saved(1);
  }
  if (ifMatch) {
    const version = parseEtag(ifMatch);
    if (version === null) return text(400, "Bad If-Match");
    const result = await db
      .prepare(
        "UPDATE groups SET blob = ?, version = version + 1, updated_at = ? WHERE id = ? AND version = ? AND auth_hash = ?",
      )
      .bind(blob, now, id, version, authHash)
      .run();
    if (result.meta.changes === 0) return conflictOrUnauthorized(db, id, authHash);
    return saved(version + 1);
  }
  return text(428, "Send If-Match or If-None-Match: *");
}

/// A write that changed nothing: someone else wrote first (412), or the token is wrong (401).
async function conflictOrUnauthorized(db, id, authHash) {
  const row = await db.prepare("SELECT auth_hash FROM groups WHERE id = ?").bind(id).first();
  if (row && row.auth_hash !== authHash) return text(401, "Wrong token");
  return text(412, "Changed since you read it");
}

function saved(version) {
  return new Response(null, { status: 204, headers: { ETag: etag(version) } });
}

function etag(version) {
  return `"${version}"`;
}

function parseEtag(value) {
  const match = /^(?:W\/)?"(\d+)"$/.exec(value.trim());
  return match ? Number(match[1]) : null;
}

function text(status, body) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function toBase64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

function fromBase64(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
