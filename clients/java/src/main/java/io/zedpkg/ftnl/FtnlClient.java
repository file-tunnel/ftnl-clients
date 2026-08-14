package io.zedpkg.ftnl;
import java.net.URI;
public record FtnlClient(URI baseUrl, String bearerToken) {
  public boolean health() { return baseUrl != null; }
}
