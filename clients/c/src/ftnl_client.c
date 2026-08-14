#include "ftnl_client.h"
ftnl_client ftnl_client_new(const char *base_url, const char *bearer_token) {
  ftnl_client value = {base_url, bearer_token}; return value;
}
bool ftnl_client_health(const ftnl_client *client) { return client != 0 && client->base_url != 0; }
