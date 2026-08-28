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

export interface FileTunnelClientOptions {
  /** Whole-request timeout. The default is 30 seconds. */
  timeoutMs?: number;
}

function internalHostAllowed(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".localhost")) return true;
  if (host === "::1" || host === "::") return true;
  if (/^f[cd][0-9a-f]*:/i.test(host) || /^fe[89ab][0-9a-f]*:/i.test(host)) return true;

  const octets = host.split(".").map(Number);
  if (octets.length === 4 && octets.every((value) => Number.isInteger(value) && value >= 0 && value <= 255)) {
    const a = octets[0]!;
    const b = octets[1]!;
    return a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168) || (a === 169 && b === 254) || a === 0;
  }

  return host !== "" && (!host.includes(".") || host.endsWith(".svc.cluster.local")
    || host.endsWith(".internal"));
}

function checkedBaseUrl(baseUrl: string): string {
  const parsed = new URL(baseUrl);
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new TypeError(
      `ftnl: unsupported URL scheme "${parsed.protocol}"; use https:// or an allowed internal http:// URL`,
    );
  }
  if (parsed.protocol === "http:" && !internalHostAllowed(parsed.hostname)) {
    throw new TypeError(
      `ftnl: refusing cleartext http:// to public host "${parsed.hostname}": `
        + "use https://, an in-cluster address, or loopback",
    );
  }
  return parsed.toString().replace(/\/+$/, "");
}

export class FileTunnelClient {
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;

  constructor(
    baseUrl: string,
    transport: typeof fetch = fetch,
    options: FileTunnelClientOptions = {},
  ) {
    this.#baseUrl = checkedBaseUrl(baseUrl);
    this.#fetch = transport;
    this.#timeoutMs = options.timeoutMs ?? 30_000;
    if (!Number.isFinite(this.#timeoutMs) || this.#timeoutMs <= 0) {
      throw new RangeError("ftnl: timeoutMs must be greater than zero");
    }
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
    const host = new URL(this.#baseUrl);
    const scheme = host.protocol === "https:" ? "wss:" : "ws:";
    const params = new URLSearchParams({ ticket: String(response.ticket) });
    return `${scheme}//${host.host}/v1/tunnels/${encodeURIComponent(tunnelId)}/events?${params}`;
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
    const response = await this.#fetch(`${this.#baseUrl}${path}`, {
      ...init,
      redirect: "error",
      signal: init?.signal ?? AbortSignal.timeout(this.#timeoutMs),
    });
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
