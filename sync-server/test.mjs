// Runs the worker against an in-memory SQLite stand-in for D1: node --test sync-server/test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import worker, { MAX_BLOB_BYTES } from "./src/index.js";

function fakeD1() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));
  return {
    prepare(sql) {
      let params = [];
      const statement = {
        bind(...values) { params = values; return statement; },
        async first() { return sqlite.prepare(sql).get(...params) ?? null; },
        async run() { const r = sqlite.prepare(sql).run(...params); return { meta: { changes: Number(r.changes) } }; },
      };
      return statement;
    },
  };
}

const id = "0123456789abcdef0123456789abcdef";
const token = "A".repeat(43);
const other = "B".repeat(43);
const blob = (n) => new Uint8Array([1, ...new Array(40).fill(n)]);

function call(env, method, { auth = token, headers = {}, body, path = `/v1/groups/${id}` } = {}) {
  const h = { ...headers };
  if (auth) h.Authorization = `Bearer ${auth}`;
  return worker.fetch(new Request(`https://sync.test${path}`, { method, headers: h, body }), env);
}

test("create, read, update with compare-and-swap", async () => {
  const env = { DB: fakeD1() };
  assert.equal((await call(env, "GET")).status, 404);

  const created = await call(env, "PUT", { headers: { "If-None-Match": "*" }, body: blob(7) });
  assert.equal(created.status, 204);
  assert.equal(created.headers.get("ETag"), '"1"');

  const again = await call(env, "PUT", { headers: { "If-None-Match": "*" }, body: blob(8) });
  assert.equal(again.status, 412);

  const read = await call(env, "GET");
  assert.equal(read.status, 200);
  assert.equal(read.headers.get("ETag"), '"1"');
  assert.deepEqual(new Uint8Array(await read.arrayBuffer()), blob(7));

  const updated = await call(env, "PUT", { headers: { "If-Match": '"1"' }, body: blob(9) });
  assert.equal(updated.status, 204);
  assert.equal(updated.headers.get("ETag"), '"2"');

  const stale = await call(env, "PUT", { headers: { "If-Match": '"1"' }, body: blob(10) });
  assert.equal(stale.status, 412);

  const latest = await call(env, "GET");
  assert.deepEqual(new Uint8Array(await latest.arrayBuffer()), blob(9));
});

test("a different token can't read or write", async () => {
  const env = { DB: fakeD1() };
  await call(env, "PUT", { headers: { "If-None-Match": "*" }, body: blob(1) });
  assert.equal((await call(env, "GET", { auth: other })).status, 401);
  assert.equal((await call(env, "PUT", { auth: other, headers: { "If-Match": '"1"' }, body: blob(2) })).status, 401);
  assert.equal((await call(env, "PUT", { auth: other, headers: { "If-None-Match": "*" }, body: blob(2) })).status, 401);
  assert.equal((await call(env, "GET", { auth: null })).status, 401);
});

test("rejects bad requests", async () => {
  const env = { DB: fakeD1() };
  assert.equal((await call(env, "PUT", { body: blob(1) })).status, 428);
  assert.equal((await call(env, "PUT", { headers: { "If-None-Match": "*" }, body: new Uint8Array([2, 3]) })).status, 400);
  const big = new Uint8Array(MAX_BLOB_BYTES + 1);
  big[0] = 1;
  assert.equal((await call(env, "PUT", { headers: { "If-None-Match": "*" }, body: big })).status, 413);
  assert.equal((await call(env, "GET", { path: "/v1/groups/xyz" })).status, 404);
  assert.equal((await call(env, "DELETE")).status, 405);
});
