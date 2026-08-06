export interface CreateTunnelOptions {
  applicationId: string;
  accept?: string[];
  maxFiles?: number;
  maxFileBytes?: number;
  expiresInSeconds?: number;
  idempotencyKey?: string;
}

export interface Tunnel {
  tunnelId: string;
  pairingUri: string;
  desktopCapability: string;
  expiresAt: string;
  status: string;
}

export interface FileDescriptor {
  file_id: string;
  name: string;
  media_type: string;
  size_bytes: number;
  bytes_transferred: number;
  status: string;
  created_at: string;
}

export interface TunnelSnapshot {
  tunnel_id: string;
  status: string;
  expires_at: string;
  files: FileDescriptor[];
}

export interface TunnelEvent {
  event_id: string;
  sequence: number;
  occurred_at: string;
  tunnel_id: string;
  kind: string;
  file_id?: string;
  bytes_transferred?: number;
  reason_code?: string;
}

export class FileTunnelError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "FileTunnelError";
  }
}

/** Host of `base` when its scheme is cleartext http://, else null. */
function cleartextHost(base: string): string | null {
  if (base.slice(0, 7).toLowerCase() !== "http://") return null;
  const authority = base.slice(7).split(/[/?#]/, 1)[0] ?? "";
  const hostPort = authority.includes("@")
    ? authority.slice(authority.lastIndexOf("@") + 1)
    : authority;
  if (hostPort.startsWith("[")) return hostPort.slice(1, hostPort.indexOf("]")).toLowerCase();
  const colon = hostPort.indexOf(":");
  return (colon === -1 ? hostPort : hostPort.slice(0, colon)).toLowerCase();
}

/** Loopback, private/link-local IPs, and in-cluster names. */
function internalHostAllowed(host: string): boolean {
  if (host === "" || host === "localhost" || host.endsWith(".localhost")) return true;
  if (host === "::1" || /^f[cd]/.test(host) || /^fe[89ab]/.test(host)) return true;
  const v4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (v4) {
    const a = Number(v4[1]);
    const b = Number(v4[2]);
    return a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168) || (a === 169 && b === 254);
  }
  return !host.includes(".") || host.endsWith(".svc.cluster.local")
    || host.endsWith(".internal");
}

/** Refuse to carry credentials over cleartext to a public host. */
function requireEncryptedTransport(baseUrl: string): void {
  const host = cleartextHost(baseUrl);
  if (host !== null && !internalHostAllowed(host)) {
    throw new TypeError(
      `ftnl: refusing cleartext http:// to public host "${host}": ` +
        "use https://, an in-cluster address, or loopback",
    );
  }
}

export class FileTunnelClient {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;

  constructor(baseUrl: string, transport: typeof fetch = fetch) {
    requireEncryptedTransport(baseUrl);
    this.#baseUrl = baseUrl.replace(/\/+$/, "");
    this.#fetch = transport;
  }

  async createTunnel(options: CreateTunnelOptions): Promise<Tunnel> {
    const response = await this.#json("/v1/tunnels", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(options.idempotencyKey ? { "idempotency-key": options.idempotencyKey } : {}),
      },
      body: JSON.stringify({
        application_id: options.applicationId,
        accept: options.accept,
        max_files: options.maxFiles,
        max_file_bytes: options.maxFileBytes,
        expires_in_seconds: options.expiresInSeconds,
      }),
    });
    return {
      tunnelId: response.tunnel_id as string,
      pairingUri: response.pairing_uri as string,
      desktopCapability: response.desktop_capability as string,
      expiresAt: response.expires_at as string,
      status: response.status as string,
    };
  }

  async claimTunnel(tunnelId: string, pairingSecret: string): Promise<string> {
    const response = await this.#json(`/v1/tunnels/${encodeURIComponent(tunnelId)}/claim`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ pairing_secret: pairingSecret }),
    });
    return response.phone_capability as string;
  }

  async snapshot(tunnelId: string, capability: string): Promise<TunnelSnapshot> {
    return (await this.#json(
      `/v1/tunnels/${encodeURIComponent(tunnelId)}`,
      this.#authorized(capability),
    )) as unknown as TunnelSnapshot;
  }

  async declareFile(
    tunnelId: string,
    capability: string,
    file: { name: string; mediaType: string; sizeBytes: number; lastModifiedMs?: number; sha256?: string },
    idempotencyKey?: string,
  ): Promise<FileDescriptor> {
    return (await this.#json(`/v1/tunnels/${encodeURIComponent(tunnelId)}/files`, {
      ...this.#authorized(capability),
      method: "POST",
      headers: {
        ...this.#authorized(capability).headers,
        "content-type": "application/json",
        ...(idempotencyKey ? { "idempotency-key": idempotencyKey } : {}),
      },
      body: JSON.stringify({
        name: file.name,
        media_type: file.mediaType,
        size_bytes: file.sizeBytes,
        last_modified_ms: file.lastModifiedMs,
        sha256: file.sha256,
      }),
    })) as unknown as FileDescriptor;
  }

  async upload(
    tunnelId: string,
    fileId: string,
    capability: string,
    bytes: BodyInit,
  ): Promise<void> {
    await this.#request(
      `/v1/tunnels/${encodeURIComponent(tunnelId)}/files/${encodeURIComponent(fileId)}/content`,
      {
        ...this.#authorized(capability),
        method: "PUT",
        headers: {
          ...this.#authorized(capability).headers,
          "content-type": "application/octet-stream",
        },
        body: bytes,
      },
    );
  }

  async download(tunnelId: string, fileId: string, capability: string): Promise<Blob> {
    const response = await this.#request(
      `/v1/tunnels/${encodeURIComponent(tunnelId)}/files/${encodeURIComponent(fileId)}/content`,
      this.#authorized(capability),
    );
    return response.blob();
  }

  async cancel(tunnelId: string, capability: string): Promise<void> {
    await this.#request(`/v1/tunnels/${encodeURIComponent(tunnelId)}`, {
      ...this.#authorized(capability),
      method: "DELETE",
    });
  }

  async eventSocketUrl(tunnelId: string, capability: string): Promise<string> {
    const response = await this.#json(
      `/v1/tunnels/${encodeURIComponent(tunnelId)}/event-tickets`,
      { ...this.#authorized(capability), method: "POST" },
    );
    const base = new URL(this.#baseUrl);
    base.protocol = base.protocol === "https:" ? "wss:" : "ws:";
    base.pathname = `/v1/tunnels/${encodeURIComponent(tunnelId)}/events`;
    base.search = new URLSearchParams({ ticket: response.ticket as string }).toString();
    return base.toString();
  }

  async connectEvents(
    tunnelId: string,
    capability: string,
    onEvent: (event: TunnelEvent) => void,
    onSequenceGap?: (expected: number, received: number) => void,
  ): Promise<WebSocket> {
    const socket = new WebSocket(await this.eventSocketUrl(tunnelId, capability));
    let lastSequence = 0;
    socket.addEventListener("message", (message) => {
      const event = JSON.parse(String(message.data)) as TunnelEvent;
      if (lastSequence && event.sequence !== lastSequence + 1) {
        onSequenceGap?.(lastSequence + 1, event.sequence);
      }
      lastSequence = Math.max(lastSequence, event.sequence);
      onEvent(event);
    });
    return socket;
  }

  #authorized(capability: string): RequestInit {
    return { headers: { authorization: `Bearer ${capability}` } };
  }

  async #json(path: string, init?: RequestInit): Promise<Record<string, unknown>> {
    const response = await this.#request(path, init);
    return (await response.json()) as Record<string, unknown>;
  }

  async #request(path: string, init?: RequestInit): Promise<Response> {
    const response = await this.#fetch(`${this.#baseUrl}${path}`, init);
    if (response.ok) return response;
    let code = "request_failed";
    let message = `File Tunnel request failed (${response.status})`;
    try {
      const problem = (await response.json()) as { code?: string; detail?: string };
      code = problem.code ?? code;
      message = problem.detail ?? message;
    } catch {
      // Never include arbitrary response content or authorization in errors.
    }
    throw new FileTunnelError(response.status, code, message);
  }
}

export const pairingSecretFromUri = (uri: string): string | undefined =>
  new URLSearchParams(new URL(uri).hash.slice(1)).get("c") ?? undefined;
