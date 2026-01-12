// Minimal readiness HTTP server (optional)
//
// Intentionally tiny and dependency-free:
// - binds to 127.0.0.1:<port>
// - accepts one request per connection
// - if it matches "GET /ready" returns 200 and {"status":"UP"}
// - otherwise returns 404

#include "ready_server.h"

#include <errno.h>
#include <string.h>

#ifdef _WIN32
// This project is primarily POSIX; readiness server is POSIX-only for now.
// Keep compilation on non-Windows by not building this file there.
#error "ready_server.c is POSIX-only"
#endif

#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

#define READY_BACKLOG 16

static pthread_t ready_thread;
static volatile int ready_running = 0;
static ready_server *ready_srv = NULL;

static void write_all(int fd, const char *buf, size_t len) {
    while (len) {
        ssize_t n = send(fd, buf, len, 0);
        if (n <= 0) return;
        buf += (size_t)n;
        len -= (size_t)n;
    }
}

static void handle_client(int cfd) {
    char req[1024];
    ssize_t n = recv(cfd, req, sizeof(req) - 1, 0);
    if (n <= 0) return;
    req[n] = '\0';

    const char *ok_body = "{\"status\":\"UP\"}";
    const char *notfound_body = "Not Found";

    // Very small parse: just inspect request line prefix.
    // Accept both HTTP/1.0 and HTTP/1.1.
    int is_ready = 0;
    if (!strncmp(req, "GET /ready ", 11) || !strncmp(req, "GET /ready\r", 10) || !strncmp(req, "GET /ready\n", 10)) {
        is_ready = 1;
    }

    if (is_ready) {
        char resp[256];
        int blen = (int)strlen(ok_body);
        int rlen = snprintf(resp, sizeof(resp),
                            "HTTP/1.1 200 OK\r\n"
                            "Content-Type: application/json\r\n"
                            "Content-Length: %d\r\n"
                            "Connection: close\r\n"
                            "\r\n"
                            "%s",
                            blen, ok_body);
        if (rlen > 0) write_all(cfd, resp, (size_t)rlen);
    } else {
        char resp[256];
        int blen = (int)strlen(notfound_body);
        int rlen = snprintf(resp, sizeof(resp),
                            "HTTP/1.1 404 Not Found\r\n"
                            "Content-Type: text/plain\r\n"
                            "Content-Length: %d\r\n"
                            "Connection: close\r\n"
                            "\r\n"
                            "%s",
                            blen, notfound_body);
        if (rlen > 0) write_all(cfd, resp, (size_t)rlen);
    }
}

static void *ready_main(void *arg) {
    (void)arg;

    while (ready_running && ready_srv && ready_srv->fd >= 0) {
        struct sockaddr_in addr;
        socklen_t alen = sizeof(addr);
        int cfd = accept(ready_srv->fd, (struct sockaddr *)&addr, &alen);
        if (cfd < 0) {
            if (errno == EINTR) continue;
            // If we're shutting down, accept may fail.
            break;
        }

        handle_client(cfd);
        close(cfd);
    }

    return NULL;
}

int ready_server_start(ready_server *srv, uint16_t port) {
    if (!srv) return -1;

    memset(srv, 0, sizeof(*srv));
    srv->fd = -1;
    srv->port = port;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);

    // Default binding: 0.0.0.0 so Docker port publishing works.
    // If you want loopback-only, set WRK2_READY_BIND=127.0.0.1
    const char *bind_ip = getenv("WRK2_READY_BIND");
    if (bind_ip && *bind_ip) {
        if (inet_pton(AF_INET, bind_ip, &addr.sin_addr) != 1) {
            close(fd);
            errno = EINVAL;
            return -1;
        }
    } else {
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
    }

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    if (listen(fd, READY_BACKLOG) < 0) {
        close(fd);
        return -1;
    }

    srv->fd = fd;

    ready_srv = srv;
    ready_running = 1;
    if (pthread_create(&ready_thread, NULL, ready_main, NULL) != 0) {
        ready_running = 0;
        ready_srv = NULL;
        close(fd);
        srv->fd = -1;
        return -1;
    }

    return 0;
}

void ready_server_stop(ready_server *srv) {
    (void)srv;

    if (!ready_running) return;
    ready_running = 0;

    if (ready_srv && ready_srv->fd >= 0) {
        // Closing the listener will unblock accept().
        close(ready_srv->fd);
        ready_srv->fd = -1;
    }

    pthread_join(ready_thread, NULL);
    ready_srv = NULL;
}