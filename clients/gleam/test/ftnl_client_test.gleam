import ftnl_client
import gleam/list
import gleam/option
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn fragment_pairing_secret_test() {
  ftnl_client.pairing_secret_from_uri(
    "https://portal.file-tunnel.dev/t/id#c=secret",
  )
  |> should.equal(option.Some("secret"))
}

pub fn public_cleartext_is_rejected_test() {
  ftnl_client.new("http://api.example.com")
  |> should.equal(Error(ftnl_client.InsecureTransport))
}

pub fn non_http_scheme_is_rejected_test() {
  ftnl_client.new("file:///tmp/socket")
  |> should.equal(Error(ftnl_client.UnsupportedScheme))
}

pub fn internal_cleartext_is_allowed_test() {
  [
    "http://127.0.0.1:8080",
    "http://[::1]:8080",
    "http://10.2.3.4",
    "http://ftnl-api",
    "http://ftnl-api.default.svc.cluster.local",
  ]
  |> list.each(fn(endpoint) {
    ftnl_client.new(endpoint)
    |> result.is_ok
    |> should.be_true
  })
}
