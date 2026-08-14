#ifndef FTNL_CLIENT_H
#define FTNL_CLIENT_H
#include <stdbool.h>
typedef struct { const char *base_url; const char *bearer_token; } ftnl_client;
ftnl_client ftnl_client_new(const char *base_url, const char *bearer_token);
bool ftnl_client_health(const ftnl_client *client);
#endif
