# syntax=docker/dockerfile:1.7

# --- Stage 1: Build wrk2 ------------------------------------------------------
FROM alpine:3.23.2 AS builder

# Toolchain + dependencies for building wrk2
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
    build-base \
    luajit \
    luajit-dev \
    openssl-dev \
    zlib-dev

WORKDIR /wrk2

# Copy only what we need to compile first (better caching). Add more paths as needed.
COPY Makefile ./
COPY src ./src
COPY scripts ./scripts
COPY deps ./deps

# Build bytecode.o using system luajit, then compile/link against system LuaJIT.
# Cache the obj directory between builds.
RUN --mount=type=cache,target=/wrk2/obj \
    set -eux; \
    CFLAGS="-std=c99 -Wall -O2 -D_REENTRANT -D_POSIX_C_SOURCE=200809L -D_BSD_SOURCE"; \
    INCLUDES="-Ideps/luajit/src -Isrc"; \
    LIBS="-lluajit-5.1 -lpthread -lm -lcrypto -lssl -ldl -lz"; \
    mkdir -p obj; \
    luajit -b /wrk2/src/wrk.lua /wrk2/obj/bytecode.o; \
    compile() { cc $CFLAGS $INCLUDES -c -o "obj/$1.o" "src/$1.c"; }; \
    compile wrk; \
    compile net; \
    compile ssl; \
    compile aprintf; \
    compile stats; \
    compile script; \
    compile units; \
    compile ae; \
    compile zmalloc; \
    compile http_parser; \
    compile tinymt64; \
    compile hdr_histogram; \
    compile ready_server; \
    cc -o wrk obj/*.o $LIBS

# --- Stage 2: Minimal runtime -------------------------------------------------
FROM alpine:3.23.2 as runtime

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
    ca-certificates \
    luajit \
    libssl3 \
    libcrypto3 \
    zlib

WORKDIR /wrk2

# Make `require("wrk")` work (the binary does `wrk = require "wrk"`).
ENV LUA_PATH="/wrk2/?.lua;/wrk2/scripts/?.lua;;"

COPY --from=builder /wrk2/wrk /wrk2/wrk
COPY --from=builder /wrk2/scripts /wrk2/scripts
COPY --from=builder /wrk2/src/wrk.lua /wrk2/wrk.lua

# Container entrypoint helper (keeps stdout/stderr flowing to Docker logs)
COPY docker/entrypoint.sh /wrk2/entrypoint.sh
RUN chmod +x /wrk2/entrypoint.sh

# Run as non-root by default.
RUN addgroup -S wrk2 && adduser -S -G wrk2 wrk2
USER wrk2

# Default: readiness-only mode (can override in compose/CLI).
ENTRYPOINT ["/wrk2/entrypoint.sh"]