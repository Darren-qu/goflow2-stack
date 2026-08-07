#!/usr/bin/env bash
# One-shot deploy for GoFlow2 + Kafka + ClickHouse + Grafana (Docker Compose).
#
# Usage:
#   ./deploy.sh
#   ./deploy.sh --geoip
#   ./deploy.sh --pull
#   sudo ./deploy.sh          # if your user is not in the docker group
#
# Env:
#   COMPOSE   override compose command (default: docker compose)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

COMPOSE="${COMPOSE:-docker compose}"
DO_GEOIP=0
DO_PULL=1

usage() {
  cat <<'EOF'
Usage: ./deploy.sh [options]

Options:
  --geoip     After up, load DB-IP GeoIP into ClickHouse (for map panels)
  --no-pull   Skip docker compose pull
  -h, --help  Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --geoip) DO_GEOIP=1; shift ;;
    --no-pull) DO_PULL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

log() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

run_compose() {
  # Prefer rootless docker; fall back to sudo if needed
  if docker info >/dev/null 2>&1; then
    ${COMPOSE} "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    sudo ${COMPOSE} "$@"
  else
    die "Docker not usable. Install Docker Compose v2, or: WITH_DOCKER=1 bash install.sh
Add your user to the docker group, or run with sudo."
  fi
}

[[ -f docker-compose.yml ]] || die "run from repo root (docker-compose.yml missing)"

command -v docker >/dev/null 2>&1 || die "docker not found. Install: https://docs.docker.com/engine/install/ or WITH_DOCKER=1 bash install.sh"

if ! docker compose version >/dev/null 2>&1 && ! sudo docker compose version >/dev/null 2>&1; then
  die "docker compose plugin not found (need Compose v2)"
fi

# LDAP secrets stay local — never commit grafana/ldap.toml
if [[ ! -f grafana/ldap.toml ]]; then
  cp grafana/ldap.toml.example grafana/ldap.toml
  log "created grafana/ldap.toml from example (edit for AD/LDAP, then: ./deploy.sh --no-pull && recreate grafana)"
fi

if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  log "created .env from .env.example — edit passwords before production use"
fi

# Load local secrets for healthchecks / messages (compose also reads .env)
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
CH_PASS="${CLICKHOUSE_PASSWORD:-flow}"
GF_USER="${GRAFANA_ADMIN_USER:-admin}"
GF_PORT="${GRAFANA_HOST_PORT:-3030}"

if [[ "${DO_PULL}" -eq 1 ]]; then
  log "pulling images..."
  run_compose pull
fi

log "starting stack..."
run_compose up -d

log "waiting for ClickHouse HTTP..."
ok=0
for _ in $(seq 1 60); do
  if run_compose exec -T db wget -q -O- 'http://127.0.0.1:8123/ping' 2>/dev/null | grep -q Ok; then
    ok=1
    break
  fi
  # alpine image may not have wget — try clickhouse-client
  if run_compose exec -T db clickhouse-client --password "${CH_PASS}" -q 'SELECT 1' >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done
[[ "${ok}" -eq 1 ]] || log "WARN: ClickHouse not ready yet; check: docker compose logs db"

# Well-known port → service name (safe on existing volumes)
if [[ "${ok}" -eq 1 ]]; then
  log "ensuring services dictionary..."
  run_compose exec -T db bash /docker-entrypoint-initdb.d/init_services.sh \
    || log "WARN: services dictionary init failed (map panels still work; service names may be port-only)"

  log "applying ClickHouse retention TTL (raw=${FLOWS_RAW_TTL_DAYS:-30}d, 5m=${FLOWS_5M_TTL_DAYS:-180}d)..."
  run_compose exec -T \
    -e "CLICKHOUSE_PASSWORD=${CH_PASS}" \
    -e "FLOWS_RAW_TTL_DAYS=${FLOWS_RAW_TTL_DAYS:-30}" \
    -e "FLOWS_5M_TTL_DAYS=${FLOWS_5M_TTL_DAYS:-180}" \
    db bash /docker-entrypoint-initdb.d/apply_retention.sh \
    || log "WARN: retention TTL apply failed — check clickhouse/apply_retention.sh"
fi

if [[ "${DO_GEOIP}" -eq 1 ]]; then
  log "loading GeoIP (may take several minutes)..."
  run_compose exec -T db bash /docker-entrypoint-initdb.d/setup_geoip.sh \
    || die "GeoIP setup failed — see clickhouse/setup_geoip.sh"
fi

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST_IP="${HOST_IP:-127.0.0.1}"

cat <<EOF

[deploy] OK

  Grafana:     http://${HOST_IP}:${GF_PORT}   (${GF_USER} / .env GRAFANA_ADMIN_PASSWORD — change if still default)
  NetFlow:     UDP ${HOST_IP}:2055
  sFlow:       UDP ${HOST_IP}:6343

  Localhost only (not LAN-exposed): ClickHouse 8123/9000, Prometheus 9090, GoFlow2 metrics 8080
  ClickHouse:  curl -u default:\${CLICKHOUSE_PASSWORD} http://127.0.0.1:8123/ping

  Status:  cd ${ROOT} && docker compose ps
  Logs:    docker compose logs -f goflow2
  LDAP:    edit grafana/ldap.toml → docker compose up -d --force-recreate grafana
           see grafana/LDAP.md
  Kafka:   after changing KAFKA_LOG_RETENTION_* always recreate together:
           docker compose up -d --force-recreate kafka goflow2 db
           (recreating kafka alone breaks the pipeline until goflow2+db reconnect)

EOF

run_compose ps
