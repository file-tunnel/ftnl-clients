//! Async Rust client for File Tunnel v1.

use bytes::Bytes;
use reqwest::{Client, Method, Response, StatusCode};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use url::Url;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct FileTunnelClient {
    base_url: Url,
    http: Client,
}

#[derive(Debug, Clone, Serialize)]
pub struct CreateTunnelRequest {
    pub application_id: String,
    pub accept: Vec<String>,
    pub max_files: u16,
    pub max_file_bytes: u64,
    pub expires_in_seconds: u32,
}

/// Whether a credential may travel to `host` in cleartext: loopback, a
/// private/link-local IP, a single-label service name, or a cluster DNS suffix.
fn cleartext_internal_host_allowed(host: &str) -> bool {
    let host = host.to_ascii_lowercase();
    if host.is_empty() || host == "localhost" || host.ends_with(".localhost") {
        return true;
    }
    if host == "::1" || host.starts_with("fc") || host.starts_with("fd") || host.starts_with("fe8")
    {
        return true;
    }
    if let Some(octets) = host
        .split('.')
        .map(str::parse::<u8>)
        .collect::<core::result::Result<Vec<_>, _>>()
        .ok()
        .filter(|octets| octets.len() == 4)
    {
        return matches!(
            (octets[0], octets[1]),
            (127, _) | (10, _) | (172, 16..=31) | (192, 168) | (169, 254)
        );
    }
    !host.contains('.') || host.ends_with(".svc.cluster.local") || host.ends_with(".internal")
}

impl CreateTunnelRequest {
    pub fn images(application_id: impl Into<String>) -> Self {
        Self {
            application_id: application_id.into(),
            accept: vec!["image/*".to_owned()],
            max_files: 10,
            max_file_bytes: 50 * 1024 * 1024,
            expires_in_seconds: 600,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Tunnel {
    pub tunnel_id: Uuid,
    pub pairing_uri: String,
    pub desktop_capability: String,
    pub expires_at: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeclareFileRequest {
    pub name: String,
    pub media_type: String,
    pub size_bytes: u64,
    pub last_modified_ms: Option<u64>,
    pub sha256: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FileDescriptor {
    pub file_id: Uuid,
    pub name: String,
    pub media_type: String,
    pub size_bytes: u64,
    pub bytes_transferred: u64,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TunnelSnapshot {
    pub tunnel_id: Uuid,
    pub status: String,
    pub expires_at: String,
    pub files: Vec<FileDescriptor>,
}

#[derive(Debug, Deserialize)]
struct ClaimResponse {
    phone_capability: String,
}

#[derive(Debug, Deserialize)]
struct TicketResponse {
    ticket: String,
}

#[derive(Debug, Deserialize)]
struct Problem {
    code: Option<String>,
    detail: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid File Tunnel base URL")]
    InvalidBaseUrl(#[source] url::ParseError),
    #[error(
        "refusing cleartext http:// to public host {0:?}: use https://, an in-cluster \
         address, or loopback"
    )]
    InsecureTransport(String),
    #[error("transport error")]
    Transport(#[source] reqwest::Error),
    #[error("File Tunnel request failed ({status}): {code}")]
    Api { status: StatusCode, code: String },
}

impl FileTunnelClient {
    pub fn new(base_url: &str) -> Result<Self, Error> {
        let mut base_url = Url::parse(base_url).map_err(Error::InvalidBaseUrl)?;
        // A bearer token must not cross a public hop in the clear.
        if base_url.scheme() == "http"
            && !cleartext_internal_host_allowed(base_url.host_str().unwrap_or_default())
        {
            return Err(Error::InsecureTransport(
                base_url.host_str().unwrap_or_default().to_owned(),
            ));
        }
        if !base_url.path().ends_with('/') {
            base_url.set_path(&format!("{}/", base_url.path()));
        }
        Ok(Self {
            base_url,
            // The default Client has no timeout and follows redirects, which
            // would replay this request — and its Authorization header — to an
            // attacker-controlled Location.
            http: Client::builder()
                .connect_timeout(std::time::Duration::from_secs(5))
                .timeout(std::time::Duration::from_secs(30))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .map_err(Error::Transport)?,
        })
    }

    pub async fn create_tunnel(&self, request: &CreateTunnelRequest) -> Result<Tunnel, Error> {
        self.json(Method::POST, "v1/tunnels", None, Some(request))
            .await
    }

    pub async fn claim_tunnel(
        &self,
        tunnel_id: Uuid,
        pairing_secret: &str,
    ) -> Result<String, Error> {
        #[derive(Serialize)]
        struct Claim<'a> {
            pairing_secret: &'a str,
        }
        let response: ClaimResponse = self
            .json(
                Method::POST,
                &format!("v1/tunnels/{tunnel_id}/claim"),
                None,
                Some(&Claim { pairing_secret }),
            )
            .await?;
        Ok(response.phone_capability)
    }

    pub async fn snapshot(
        &self,
        tunnel_id: Uuid,
        capability: &str,
    ) -> Result<TunnelSnapshot, Error> {
        self.json::<TunnelSnapshot, ()>(
            Method::GET,
            &format!("v1/tunnels/{tunnel_id}"),
            Some(capability),
            None,
        )
        .await
    }

    pub async fn declare_file(
        &self,
        tunnel_id: Uuid,
        capability: &str,
        request: &DeclareFileRequest,
    ) -> Result<FileDescriptor, Error> {
        self.json(
            Method::POST,
            &format!("v1/tunnels/{tunnel_id}/files"),
            Some(capability),
            Some(request),
        )
        .await
    }

    pub async fn upload(
        &self,
        tunnel_id: Uuid,
        file_id: Uuid,
        capability: &str,
        bytes: Bytes,
    ) -> Result<(), Error> {
        let response = self
            .request(
                Method::PUT,
                &format!("v1/tunnels/{tunnel_id}/files/{file_id}/content"),
                Some(capability),
            )?
            .header("content-type", "application/octet-stream")
            .body(bytes)
            .send()
            .await
            .map_err(Error::Transport)?;
        self.ensure_success(response).await?;
        Ok(())
    }

    pub async fn download(
        &self,
        tunnel_id: Uuid,
        file_id: Uuid,
        capability: &str,
    ) -> Result<Bytes, Error> {
        let response = self
            .request(
                Method::GET,
                &format!("v1/tunnels/{tunnel_id}/files/{file_id}/content"),
                Some(capability),
            )?
            .send()
            .await
            .map_err(Error::Transport)?;
        self.ensure_success(response)
            .await?
            .bytes()
            .await
            .map_err(Error::Transport)
    }

    pub async fn cancel(&self, tunnel_id: Uuid, capability: &str) -> Result<(), Error> {
        let response = self
            .request(
                Method::DELETE,
                &format!("v1/tunnels/{tunnel_id}"),
                Some(capability),
            )?
            .send()
            .await
            .map_err(Error::Transport)?;
        self.ensure_success(response).await?;
        Ok(())
    }

    pub async fn event_socket_url(&self, tunnel_id: Uuid, capability: &str) -> Result<Url, Error> {
        let ticket: TicketResponse = self
            .json::<TicketResponse, ()>(
                Method::POST,
                &format!("v1/tunnels/{tunnel_id}/event-tickets"),
                Some(capability),
                None,
            )
            .await?;
        let mut url = self
            .base_url
            .join(&format!("v1/tunnels/{tunnel_id}/events"))
            .expect("validated base URL can join a relative route");
        url.set_scheme(if url.scheme() == "https" { "wss" } else { "ws" })
            .expect("http and https URLs support ws scheme replacement");
        url.query_pairs_mut().append_pair("ticket", &ticket.ticket);
        Ok(url)
    }

    fn request(
        &self,
        method: Method,
        path: &str,
        capability: Option<&str>,
    ) -> Result<reqwest::RequestBuilder, Error> {
        let url = self.base_url.join(path).map_err(Error::InvalidBaseUrl)?;
        let request = self.http.request(method, url);
        Ok(match capability {
            Some(value) => request.bearer_auth(value),
            None => request,
        })
    }

    async fn json<T, B>(
        &self,
        method: Method,
        path: &str,
        capability: Option<&str>,
        body: Option<&B>,
    ) -> Result<T, Error>
    where
        T: DeserializeOwned,
        B: Serialize + ?Sized,
    {
        let mut request = self.request(method, path, capability)?;
        if let Some(body) = body {
            request = request.json(body);
        }
        let response = request.send().await.map_err(Error::Transport)?;
        self.ensure_success(response)
            .await?
            .json()
            .await
            .map_err(Error::Transport)
    }

    async fn ensure_success(&self, response: Response) -> Result<Response, Error> {
        if response.status().is_success() {
            return Ok(response);
        }
        let status = response.status();
        let problem = response.json::<Problem>().await.ok();
        let _redacted_detail = problem.as_ref().and_then(|value| value.detail.as_deref());
        Err(Error::Api {
            status,
            code: problem
                .and_then(|value| value.code)
                .unwrap_or_else(|| "request_failed".to_owned()),
        })
    }
}

pub fn pairing_secret_from_uri(uri: &str) -> Option<String> {
    Url::parse(uri)
        .ok()?
        .fragment()
        .and_then(|fragment| {
            url::form_urlencoded::parse(fragment.as_bytes()).find(|(key, _)| key == "c")
        })
        .map(|(_, value)| value.into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_image_tunnel_is_bounded() {
        let request = CreateTunnelRequest::images("tests");
        assert_eq!(request.accept, ["image/*"]);
        assert_eq!(request.max_files, 10);
        assert!(request.expires_in_seconds <= 3600);
    }

    #[test]
    fn pairing_secret_is_fragment_only() {
        assert_eq!(
            pairing_secret_from_uri("https://portal.test/t/id#c=secret"),
            Some("secret".to_owned())
        );
        assert_eq!(
            pairing_secret_from_uri("https://portal.test/t/id?c=leaky"),
            None
        );
    }

    proptest::proptest! {
        #[test]
        fn every_utf8_pairing_secret_round_trips_through_the_fragment(secret in ".*") {
            let fragment = url::form_urlencoded::Serializer::new(String::new())
                .append_pair("c", &secret)
                .finish();
            let uri = format!("https://portal.test/t/id#{fragment}");
            proptest::prop_assert_eq!(pairing_secret_from_uri(&uri), Some(secret));
        }

        #[test]
        fn query_parameters_never_become_pairing_secrets(secret in ".*") {
            let query = url::form_urlencoded::Serializer::new(String::new())
                .append_pair("c", &secret)
                .finish();
            let uri = format!("https://portal.test/t/id?{query}");
            proptest::prop_assert_eq!(pairing_secret_from_uri(&uri), None);
        }
    }
}
