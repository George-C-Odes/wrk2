#!/usr/bin/env sh
set -eu

# Simple entrypoint for container usage.
#
# Goal: always stream wrk2 output to the Docker logs (stdout/stderr).
# - Use exec so signals (CTRL+C/docker stop) are delivered to wrk2.
# - Don't swallow output; just run the command.

# Helpful banner for docker logs
echo "[wrk2] container entrypoint starting" >&2

# Networking/debug helpers
READY_BIND="${WRK2_READY_BIND:-0.0.0.0}"
echo "[wrk2] readiness bind address: ${READY_BIND}" >&2

# Best-effort display of container IPs (may show multiple if present)
IP_CANDIDATES=""
if command -v hostname >/dev/null 2>&1; then
  IP_CANDIDATES="$(hostname -i 2>/dev/null || true)"
  if [ -n "${IP_CANDIDATES}" ]; then
    echo "[wrk2] container IP(s): ${IP_CANDIDATES}" >&2
  fi
fi

# Fallback for minimal images where hostname -i may not be available/accurate
if [ -z "${IP_CANDIDATES}" ] && command -v ip >/dev/null 2>&1; then
  IP_CANDIDATES="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd' ' - || true)"
  if [ -n "${IP_CANDIDATES}" ]; then
    echo "[wrk2] container IP(s): ${IP_CANDIDATES}" >&2
  fi
fi

# Ready URL hints
echo "[wrk2] ready URL (inside container): http://127.0.0.1:3003/ready" >&2
if [ "${READY_BIND}" = "127.0.0.1" ]; then
  echo "[wrk2] note: WRK2_READY_BIND=127.0.0.1 makes readiness loopback-only (not reachable via published ports)" >&2
else
  echo "[wrk2] ready URL (bind): http://${READY_BIND}:3003/ready" >&2
  echo "[wrk2] ready URL (host): http://localhost:3003/ready" >&2
fi

if [ -x /wrk2/wrk ]; then
  # Best-effort version output (don't fail container if it errors)
  /wrk2/wrk -v >/dev/null 2>&1 && /wrk2/wrk -v >&2 || true
fi

if [ "$#" -eq 0 ]; then
  # Default to readiness-only mode on 3003 when no args are provided.
  echo "[wrk2] no command provided; starting readiness-only mode" >&2
  echo "[wrk2] tip: single execution mode (one-shot benchmark): docker compose -f docker/docker-compose.yml run --rm wrk2 /wrk2/wrk -t2 -c10 -d10s -R1000 http://example.com/" >&2
  echo "[wrk2] tip: to get a shell: docker exec -it wrk2 sh" >&2
  set -- /wrk2/wrk --ready-port 3003
else
  echo "[wrk2] executing: $*" >&2
fi

exec "$@"