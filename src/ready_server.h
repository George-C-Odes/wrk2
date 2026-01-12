// Minimal readiness HTTP server (optional)
// Exposes GET /ready -> 200 {"status":"UP"}

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ready_server {
    int fd;
    uint16_t port;
} ready_server;

// Start a readiness server on 127.0.0.1:<port>. Returns 0 on success.
int ready_server_start(ready_server *srv, uint16_t port);

// Stop server (safe to call multiple times).
void ready_server_stop(ready_server *srv);

#ifdef __cplusplus
}
#endif