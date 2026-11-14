# Hushtype sync

Keeps the dictionary and snippets in step across a person's Macs, iPhone and Android phone. There are no
accounts. One device makes a random secret and the others get it by scanning a QR code (or typing the
code on a Mac). Everything is encrypted on the device with keys derived from that secret, so this server
only ever stores data it can't read.

The Swift side lives in `Sources/HushtypeCore/Sync*.swift` and the Android side in hushtype-android's
`data/VocabularyRepository.kt`. **Change all of them together.** `reference.mjs` prints the test
vectors that both test suites check.

## Pairing code

- The secret is 32 random bytes.
- The pairing code is `HT1-` followed by the secret in [Crockford base32](https://www.crockford.com/base32.html)
  (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, no padding, 52 characters), in dash-separated groups of four.
  The QR code holds exactly this text.
- When reading a code, ignore case and anything that isn't a letter or digit, and read `O` as `0` and
  `I`/`L` as `1`. It must start with `HT1` and decode to 32 bytes.

## Keys

All three come from HKDF-SHA256 with the secret as input key material, the salt `hushtype-sync-v1` (UTF-8)
and 32 bytes of output. Only the `info` label differs:

| info | use |
| --- | --- |
| `group-id` | first 16 bytes, lowercase hex (32 characters): the group's id on the server |
| `auth` | base64url without padding (43 characters): sent as `Authorization: Bearer …` |
| `encryption` | the AES-256-GCM key |

## Blob

The server stores one blob per group: byte `0x01`, then a random 12-byte nonce, the AES-256-GCM ciphertext
and the 16-byte tag. The associated data is the group id (its 32 hex characters, UTF-8). The plaintext is
UTF-8 JSON:

```json
{
  "terms": [
    {"text": "Kubernetes", "createdAt": 1763100000000, "updatedAt": 1763100000000, "deleted": false, "learned": true}
  ],
  "snippets": [
    {"id": "6f1c2b8e-1d5a-4c1e-9a77-1b2c3d4e5f60", "trigger": "my link", "expansion": "https://cal.com/x",
     "createdAt": 1763100000000, "updatedAt": 1763100000001, "deleted": false}
  ]
}
```

Times are epoch milliseconds. Ignore unknown fields so later versions can add some.

## Merging

- A term's key is its text, trimmed and lowercased. A snippet's key is its id, lowercased.
- For each key, the item with the larger `updatedAt` wins. On a tie, the device's own copy wins.
- A removal is a tombstone (`deleted: true` with a new `updatedAt`), never a missing item.
- Tombstones older than 30 days are dropped before uploading.
- Every local add, edit or removal sets `updatedAt` to now (and always to more than the old value).

## Server API

`GET /v1/groups/{groupId}`, with the bearer token:
- `200` with the blob and `ETag: "<version>"`
- `404` when no device has written yet
- `401` when the token doesn't match the one that created the group

`PUT /v1/groups/{groupId}`, with the bearer token and the blob as the body (at most 512 KB):
- With `If-None-Match: *`, it creates the group. The token's SHA-256 is stored, and later requests must use the same token.
- With `If-Match: "<version>"`, it replaces the blob only if nothing changed since that version.
- Returns `204` with the new `ETag`, `412` if someone else wrote first (fetch, merge and try again),
  `401`, `413` or `428` (no condition header).

A device syncs like this. Fetch the blob. Merge it with the device's own copy and apply the result locally.
If the result differs from what the server had, `PUT` it with the version you read. If that returns `412`,
start over. Sync on launch, a couple of seconds after a local edit, and every few minutes while the app runs.

## Running the server

It's a Cloudflare Worker with a D1 database.

```sh
cd sync-server
npx wrangler d1 create hushtype-sync          # put the database_id in wrangler.toml
npx wrangler d1 execute hushtype-sync --remote --file=schema.sql
npx wrangler deploy
node --test test.mjs                          # tests, with SQLite standing in for D1
```

To use your own server, point `SyncClient.defaultServer` (and the Android equivalent) at it.
