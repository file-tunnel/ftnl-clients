import ftnl_client
import gleam/option
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
