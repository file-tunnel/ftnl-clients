/// Transport-neutral request builders for File Tunnel v1.
///
/// The caller executes the returned `gleam_http.Request(String)` with their
/// preferred BEAM or JavaScript transport. Keeping I/O outside this module
/// makes retry and capability persistence explicit.
import gleam/http
import gleam/http/request.{type Request}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

pub type Client {
  Client(base_url: String)
}

pub type ClientError {
  InvalidBaseUrl
  UnsupportedScheme
  InsecureTransport
  InvalidTunnelId
}

pub fn new(base_url: String) -> Result(Client, ClientError) {
  case uri.parse(base_url) {
    Ok(parsed) -> {
      use _ <- result.try(check_transport(parsed))
      let normalized = case string.ends_with(base_url, "/") {
        True -> string.drop_end(base_url, 1)
        False -> base_url
      }
      Ok(Client(base_url: normalized))
    }
    Error(_) -> Error(InvalidBaseUrl)
  }
}

fn check_transport(parsed: uri.Uri) -> Result(Nil, ClientError) {
  case parsed.scheme, parsed.host {
    Some("https"), Some(_) -> Ok(Nil)
    Some("http"), Some(host) ->
      case internal_host_allowed(string.lowercase(host)) {
        True -> Ok(Nil)
        False -> Error(InsecureTransport)
      }
    Some(_), _ -> Error(UnsupportedScheme)
    _, _ -> Error(InvalidBaseUrl)
  }
}

fn internal_host_allowed(host: String) -> Bool {
  host == "localhost"
  || string.ends_with(host, ".localhost")
  || host == "::1"
  || host == "::"
  || string.starts_with(host, "fc")
  || string.starts_with(host, "fd")
  || string.starts_with(host, "fe8")
  || string.starts_with(host, "fe9")
  || string.starts_with(host, "fea")
  || string.starts_with(host, "feb")
  || private_ipv4(host)
  || {
    !string.contains(host, ".")
    || string.ends_with(host, ".svc.cluster.local")
    || string.ends_with(host, ".internal")
  }
}

fn private_ipv4(host: String) -> Bool {
  case string.split(host, ".") {
    [a, b, c, d] ->
      case int.parse(a), int.parse(b), int.parse(c), int.parse(d) {
        Ok(a), Ok(b), Ok(c), Ok(d)
          if a >= 0
          && a <= 255
          && b >= 0
          && b <= 255
          && c >= 0
          && c <= 255
          && d >= 0
          && d <= 255
        ->
          a == 127
          || a == 10
          || { a == 172 && b >= 16 && b <= 31 }
          || { a == 192 && b == 168 }
          || { a == 169 && b == 254 }
          || a == 0
        _, _, _, _ -> False
      }
    _ -> False
  }
}

pub fn create_tunnel_request(
  client: Client,
  application_id: String,
) -> Request(String) {
  let Client(base_url) = client
  let body =
    json.object([
      #("application_id", json.string(application_id)),
      #("accept", json.array([json.string("image/*")], fn(value) { value })),
      #("max_files", json.int(10)),
      #("max_file_bytes", json.int(50 * 1024 * 1024)),
      #("expires_in_seconds", json.int(600)),
    ])
    |> json.to_string
  let assert Ok(req) = request.to(base_url <> "/v1/tunnels")
  req
  |> request.set_method(http.Post)
  |> request.set_header("content-type", "application/json")
  |> request.set_body(body)
}

pub fn snapshot_request(
  client: Client,
  tunnel_id: String,
  capability: String,
) -> Request(String) {
  request(client, http.Get, "/v1/tunnels/" <> tunnel_id, capability)
}

pub fn cancel_request(
  client: Client,
  tunnel_id: String,
  capability: String,
) -> Request(String) {
  request(client, http.Delete, "/v1/tunnels/" <> tunnel_id, capability)
}

pub fn event_ticket_request(
  client: Client,
  tunnel_id: String,
  capability: String,
) -> Request(String) {
  request(
    client,
    http.Post,
    "/v1/tunnels/" <> tunnel_id <> "/event-tickets",
    capability,
  )
}

fn request(
  client: Client,
  method: http.Method,
  path: String,
  capability: String,
) -> Request(String) {
  let Client(base_url) = client
  let assert Ok(req) = request.to(base_url <> path)
  req
  |> request.set_method(method)
  |> request.set_header("authorization", "Bearer " <> capability)
}

pub fn pairing_secret_from_uri(value: String) -> Option(String) {
  case uri.parse(value) {
    Error(_) -> None
    Ok(parsed) ->
      case parsed.fragment {
        None -> None
        Some(fragment) ->
          case uri.parse_query(fragment) {
            Error(_) -> None
            Ok(pairs) ->
              case list.key_find(pairs, "c") {
                Error(_) -> None
                Ok(secret) -> Some(secret)
              }
          }
      }
  }
}
