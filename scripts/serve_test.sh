#!/usr/bin/env bash
# Usage: serve_test.sh <image> [port]
#
# Cloud Build runs each step in its own container, so a published port is not
# reachable at localhost there. When the "cloudbuild" docker network exists the
# server joins it and is addressed by container name, which the step can reach.
# Otherwise the port is published and addressed on localhost.
set -euo pipefail

IMAGE="${1:?image required}"
PORT="${2:-8080}"
NAME="serve-test-$$"

if docker network inspect cloudbuild >/dev/null 2>&1; then
  NET=(--network cloudbuild)
  BASE="http://${NAME}:8080"
else
  NET=(-p "${PORT}:8080")
  BASE="http://localhost:${PORT}"
fi

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" \
  "${NET[@]}" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=8m \
  --tmpfs /var/cache/nginx:rw,noexec,nosuid,size=16m \
  --tmpfs /var/run:rw,noexec,nosuid,size=1m \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  "$IMAGE" >/dev/null

echo "testing ${BASE}"

fail() { echo "FAIL: $*" >&2; docker logs "$NAME" 2>&1 | tail -20 >&2; exit 1; }

ready=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE}/healthz" 2>/dev/null; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || fail "server never became ready at ${BASE}"

code() { curl -sS -o /dev/null -w '%{http_code}' "$@" 2>/dev/null; }

expect() {
  local want="$1" got="$2" what="$3"
  [ "$got" = "$want" ] || fail "$what: got $got want $want"
  printf '  ok  %-28s %s\n' "$what" "$got"
}

echo "status codes:"
expect 200 "$(code "${BASE}/")"            "GET /"
expect 200 "$(code "${BASE}/healthz")"     "GET /healthz"
expect 404 "$(code "${BASE}/nope")"        "GET missing"
expect 404 "$(code "${BASE}/.git/config")" "GET dotfile"
expect 405 "$(code -X POST "${BASE}/")"    "POST /"

echo "headers:"
HDRS="$(curl -sS -D - -o /dev/null "${BASE}/" 2>/dev/null)"
for h in Content-Security-Policy Strict-Transport-Security X-Content-Type-Options \
         X-Frame-Options Referrer-Policy Permissions-Policy; do
  echo "$HDRS" | grep -iq "^${h}:" || fail "missing header: $h"
  printf '  ok  %s\n' "$h"
done

echo "$HDRS" | grep -iq "content-security-policy:.*script-src '\?sha256-" \
  || fail "CSP has no script hash"
echo "  ok  CSP carries a script hash"

if echo "$HDRS" | grep -iq "content-security-policy:.*script-src[^;]*unsafe-inline"; then
  fail "CSP allows unsafe-inline scripts"
fi
echo "  ok  CSP has no unsafe-inline for scripts"

if echo "$HDRS" | grep -iqE "^server:.*nginx/[0-9]"; then
  fail "Server header leaks a version"
fi
echo "  ok  Server header has no version"

echo "headers on error responses:"
curl -sS -D - -o /dev/null "${BASE}/nope" 2>/dev/null | grep -iq "^content-security-policy:" \
  || fail "404 is missing CSP"
echo "  ok  404 carries CSP"

echo "runtime user:"
UID_OUT="$(docker run --rm --entrypoint id "$IMAGE" -u)"
[ "$UID_OUT" != "0" ] || fail "container runs as root"
echo "  ok  uid $UID_OUT"

echo "content is not writable by the server user:"
if docker exec "$NAME" sh -c 'touch /usr/share/nginx/html/probe' 2>/dev/null; then
  fail "content directory is writable"
fi
echo "  ok  content directory is read-only"

echo "all serve tests passed"
