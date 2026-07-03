#!/usr/bin/env bash
# Start the UrbanSatna backend with its dependencies (PostgreSQL + Redis).
#
#   ./start.sh             # dev build
#   ./start.sh --release   # optimized build
#
# Dependency strategy: use whatever is already listening on the ports from
# backend/.env; otherwise try docker compose (infra/docker-compose.yml);
# for Redis, fall back to a local redis-server if installed. This keeps the
# script working both on machines with Docker and on this repo's dev Mac,
# where Docker is unavailable and Postgres.app + brew redis are used.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$ROOT/backend"
COMPOSE_FILE="$ROOT/infra/docker-compose.yml"

log() { printf '\033[1;34m[start]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[start]\033[0m %s\n' "$*" >&2; exit 1; }

# --- environment --------------------------------------------------------
cd "$BACKEND"
if [ ! -f .env ]; then
  log "no backend/.env found — creating one from .env.example"
  cp .env.example .env
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a
: "${DATABASE_URL:?DATABASE_URL missing in backend/.env}"
: "${REDIS_URL:?REDIS_URL missing in backend/.env}"

# postgres://user:pass@host:port/db -> host:port
hostport() { printf '%s' "$1" | sed -E 's#^[a-z]+://##; s#^[^@/]*@##; s#[/?].*$##'; }

DB_HP="$(hostport "$DATABASE_URL")"
DB_HOST="${DB_HP%%:*}"
DB_PORT="${DB_HP##*:}"
[ "$DB_PORT" = "$DB_HOST" ] && DB_PORT=5432

RD_HP="$(hostport "$REDIS_URL")"
RD_HOST="${RD_HP%%:*}"
RD_PORT="${RD_HP##*:}"
[ "$RD_PORT" = "$RD_HOST" ] && RD_PORT=6379

port_open() { nc -z "$1" "$2" >/dev/null 2>&1; }

wait_for() { # host port
  for _ in $(seq 1 30); do
    port_open "$1" "$2" && return 0
    sleep 1
  done
  return 1
}

compose_up() { # service...
  docker info >/dev/null 2>&1 || return 1
  docker compose -f "$COMPOSE_FILE" up -d --wait "$@"
}

# --- postgres -----------------------------------------------------------
if port_open "$DB_HOST" "$DB_PORT"; then
  log "PostgreSQL reachable at $DB_HOST:$DB_PORT"
else
  log "PostgreSQL not reachable at $DB_HOST:$DB_PORT — trying docker compose"
  compose_up postgres || true
  wait_for "$DB_HOST" "$DB_PORT" || die \
    "PostgreSQL is not reachable at $DB_HOST:$DB_PORT.
Start it (Postgres.app, or: docker compose -f infra/docker-compose.yml up -d postgres)
or fix DATABASE_URL in backend/.env."
fi

# --- redis ---------------------------------------------------------------
if port_open "$RD_HOST" "$RD_PORT"; then
  log "Redis reachable at $RD_HOST:$RD_PORT"
else
  case "$RD_HOST" in
    localhost|127.0.0.1)
      if command -v redis-server >/dev/null 2>&1; then
        log "starting local redis-server on port $RD_PORT (daemonized)"
        redis-server --daemonize yes --port "$RD_PORT"
      else
        log "Redis not reachable — trying docker compose"
        compose_up redis || true
      fi
      ;;
    *)
      log "Redis not reachable — trying docker compose"
      compose_up redis || true
      ;;
  esac
  wait_for "$RD_HOST" "$RD_PORT" || die \
    "Redis is not reachable at $RD_HOST:$RD_PORT.
Install it (brew install redis) or start it via docker compose,
or fix REDIS_URL in backend/.env."
fi

# --- run ------------------------------------------------------------------
PROFILE=""
if [ "${1:-}" = "--release" ]; then
  PROFILE="--release"
fi
log "dependencies ready — starting urbansatna-api (${PROFILE:-dev})"
log "health: http://localhost:${APP_PORT:-8080}/health"
# exec: the API becomes the foreground process; Ctrl-C stops it gracefully.
exec cargo run $PROFILE
