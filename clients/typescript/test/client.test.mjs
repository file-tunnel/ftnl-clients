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
