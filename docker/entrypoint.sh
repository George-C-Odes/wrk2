#!/usr/bin/env sh
set -eu

# Simple entrypoint for container usage.
#
# - Starts a minimal readiness endpoint using busybox httpd.
# - Keeps stdout/stderr flowing to Docker logs.
# - Allows overriding the command to run wrk2 manually.

echo "[wrk2] container entrypoint starting" >&2

READY_BIND="${WRK2_READY_BIND:-0.0.0.0}"
READY_PORT="${WRK2_READY_PORT:-3003}"
echo "[wrk2] readiness bind address: ${READY_BIND}" >&2

echo "[wrk2] readiness will listen on: ${READY_BIND}:${READY_PORT}" >&2

# Best-effort display of container IPs
IP_CANDIDATES=""
if command -v hostname >/dev/null 2>&1; then
  IP_CANDIDATES="$(hostname -i 2>/dev/null || true)"
  if [ -n "${IP_CANDIDATES}" ]; then
    echo "[wrk2] container IP(s): ${IP_CANDIDATES}" >&2
  fi
fi
if [ -z "${IP_CANDIDATES}" ] && command -v ip >/dev/null 2>&1; then
  IP_CANDIDATES="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd' ' - || true)"
  if [ -n "${IP_CANDIDATES}" ]; then
    echo "[wrk2] container IP(s): ${IP_CANDIDATES}" >&2
  fi
fi

# Create docroot for readiness
DOCROOT="${WRK2_READY_DOCROOT:-/tmp/wrk2-ready}"
mkdir -p "${DOCROOT}"

# Serve /ready as a file (avoids 302 redirect from /ready -> /ready/).
# BusyBox httpd maps URLs to files under DOCROOT.
READY_JSON_PATH="${DOCROOT}/ready"

# Body requested by user (now real JSON)
printf "%s\n" '{"status":"UP"}' > "${READY_JSON_PATH}"

# Configure BusyBox httpd to emit correct Content-Type for JSON
# (-c points at this file).
HTTPD_CONF="${DOCROOT}/httpd.conf"
cat > "${HTTPD_CONF}" <<'EOF'
# BusyBox httpd config
# Ensure JSON content type
*.json:text/json
*.js:application/javascript
EOF

# If we serve /ready without extension, BusyBox will default to text/plain.
# We can instead serve /ready.json and keep /ready as a symlink, but symlink may be disabled on some FS.
# So: write /ready.json and copy to /ready at startup and set text/json above for *.json.
READY_JSON_EXT_PATH="${DOCROOT}/ready.json"
printf "%s\n" '{"status":"UP"}' > "${READY_JSON_EXT_PATH}"
# Keep /ready as a plain file too (no redirect). It will be text/plain, but still valid JSON.
# If you want strict content-type, hit /ready.json.

echo "[wrk2] ready URL (inside container): http://127.0.0.1:${READY_PORT}/ready" >&2
echo "[wrk2] ready URL (inside container, typed): http://127.0.0.1:${READY_PORT}/ready.json" >&2
if [ "${READY_BIND}" = "127.0.0.1" ]; then
  echo "[wrk2] note: WRK2_READY_BIND=127.0.0.1 makes readiness loopback-only (not reachable via published ports)" >&2
else
  echo "[wrk2] ready URL (bind): http://${READY_BIND}:${READY_PORT}/ready" >&2
  echo "[wrk2] ready URL (host): http://localhost:${READY_PORT}/ready" >&2
fi

if [ -x /wrk2/wrk ]; then
  /wrk2/wrk -v >/dev/null 2>&1 && /wrk2/wrk -v >&2 || true
fi

if [ "$#" -eq 0 ]; then
  echo "[wrk2] no command provided; starting readiness server" >&2
  echo "[wrk2] tip: interactive mode: docker exec -it wrk2 sh" >&2
  echo "[wrk2] tip: one-shot benchmark: docker compose -f docker/docker-compose.yml run --rm wrk2 /wrk2/wrk -t2 -c10 -d10s -R1000 http://example.com/" >&2

  # Start busybox httpd in foreground so container stays alive.
  # -f: foreground, -v: verbose, -p: address:port, -h: docroot, -c: config
  exec httpd -f -v -p "${READY_BIND}:${READY_PORT}" -h "${DOCROOT}" -c "${HTTPD_CONF}"
fi

echo "[wrk2] executing: $*" >&2
exec "$@"