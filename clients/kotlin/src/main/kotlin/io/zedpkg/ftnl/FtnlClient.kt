package io.zedpkg.ftnl
import java.net.URI
data class FtnlClient(val baseUrl: URI, val bearerToken: String? = null) {
  suspend fun health(): Boolean = baseUrl.toString().isNotEmpty()
}
