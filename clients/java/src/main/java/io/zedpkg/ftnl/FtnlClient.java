package io.zedpkg.ftnl;
import java.net.URI;
public record FtnlClient(URI baseUri, String bearerToken) {}
