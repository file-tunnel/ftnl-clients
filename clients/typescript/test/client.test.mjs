import assert from "node:assert/strict";
import { test } from "node:test";
import { FileTunnelClient, pairingSecretFromUri } from "../dist/index.js";

test("create maps idiomatic options to the wire contract", async () => {
  let request;
  const transport = async (url, init) => {
    request = { url, init };
    return new Response(JSON.stringify({
      tunnel_id: "id",
      pairing_uri: "https://portal/t/id#c=secret",
      desktop_capability: "desktop",
      expires_at: "2026-07-29T00:00:00Z",
      status: "waiting",
    }), { status: 201, headers: { "content-type": "application/json" } });
  };
  const client = new FileTunnelClient("https://api.test/", transport);
  const tunnel = await client.createTunnel({ applicationId: "host", maxFiles: 4 });
  assert.equal(request.url, "https://api.test/v1/tunnels");
  assert.equal(JSON.parse(request.init.body).application_id, "host");
  assert.equal(tunnel.desktopCapability, "desktop");
});

test("pairing helpers accept fragment credentials only", () => {
  assert.equal(pairingSecretFromUri("https://p.test/t/id#c=secret"), "secret");
  assert.equal(pairingSecretFromUri("https://p.test/t/id?c=leak"), undefined);
});

test("public cleartext and non-HTTP schemes are rejected", () => {
  assert.throws(() => new FileTunnelClient("http://api.example.com"), /refusing cleartext/);
  assert.throws(() => new FileTunnelClient("file:///tmp/socket"), /unsupported URL scheme/);
});

test("cleartext remains available for trusted local and in-cluster endpoints", () => {
  for (const endpoint of [
    "http://127.0.0.1:8080",
    "http://[::1]:8080",
    "http://10.2.3.4",
    "http://ftnl-api",
    "http://ftnl-api.default.svc.cluster.local",
  ]) {
    assert.doesNotThrow(() => new FileTunnelClient(endpoint, async () => new Response()));
  }
});

test("timeout must be positive and redirects are refused", async () => {
  assert.throws(
    () => new FileTunnelClient("https://api.example.com", fetch, { timeoutMs: 0 }),
    /greater than zero/,
  );
  let request;
  const client = new FileTunnelClient("https://api.example.com", async (_url, init) => {
    request = init;
    return new Response(JSON.stringify({}), { status: 200 });
  }, { timeoutMs: 250 });
  await client.createTunnel({ applicationId: "test" });
  assert.equal(request.redirect, "error");
  assert.ok(request.signal instanceof AbortSignal);
});
