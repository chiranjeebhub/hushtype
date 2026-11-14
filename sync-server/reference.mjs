// A small reference of the sync format in plain JavaScript, used to make test vectors that the
// Swift and Kotlin tests check against: node sync-server/reference.mjs
import { hkdfSync, createCipheriv, createDecipheriv } from "node:crypto";

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export function derive(secret, label) {
  return Buffer.from(hkdfSync("sha256", secret, Buffer.from("hushtype-sync-v1"), Buffer.from(label), 32));
}

export function groupID(secret) {
  return derive(secret, "group-id").subarray(0, 16).toString("hex");
}

export function authToken(secret) {
  return derive(secret, "auth").toString("base64url");
}

export function crockford(bytes) {
  let out = "", buffer = 0, bits = 0;
  for (const byte of bytes) {
    buffer = ((buffer << 8) | byte) & 0xffff;
    bits += 8;
    while (bits >= 5) { out += ALPHABET[(buffer >> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += ALPHABET[(buffer << (5 - bits)) & 31];
  return out;
}

export function pairingCode(secret) {
  return "HT1-" + crockford(secret).match(/.{1,4}/g).join("-");
}

export function seal(secret, json, nonce) {
  const key = derive(secret, "encryption");
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(groupID(secret)));
  const body = Buffer.concat([cipher.update(Buffer.from(json)), cipher.final()]);
  return Buffer.concat([Buffer.from([1]), nonce, body, cipher.getAuthTag()]);
}

export function open(secret, blob) {
  const key = derive(secret, "encryption");
  const decipher = createDecipheriv("aes-256-gcm", key, blob.subarray(1, 13));
  decipher.setAAD(Buffer.from(groupID(secret)));
  decipher.setAuthTag(blob.subarray(blob.length - 16));
  return Buffer.concat([decipher.update(blob.subarray(13, blob.length - 16)), decipher.final()]).toString();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const secret = Buffer.from([...Array(32).keys()]);
  const nonce = Buffer.from([...Array(12).keys()].map((i) => 0xa0 + i));
  const json = JSON.stringify({
    terms: [{ text: "Kubernetes", createdAt: 1763100000000, updatedAt: 1763100000000, deleted: false, learned: true }],
    snippets: [{ id: "6f1c2b8e-1d5a-4c1e-9a77-1b2c3d4e5f60", trigger: "my link", expansion: "https://cal.com/x",
      createdAt: 1763100000000, updatedAt: 1763100000001, deleted: false }],
  });
  const blob = seal(secret, json, nonce);
  console.log(JSON.stringify({
    secretHex: secret.toString("hex"),
    groupID: groupID(secret),
    authToken: authToken(secret),
    pairingCode: pairingCode(secret),
    plaintext: json,
    blobBase64: blob.toString("base64"),
  }, null, 2));
  if (open(secret, blob) !== json) throw new Error("round trip failed");
}
