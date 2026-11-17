#!/usr/bin/env bash
# Back up everything that cannot be recreated from the git repo:
#   .env, grafana/ldap.toml, alertmanager/alertmanager.yml, and Grafana's
#   database (users, preferences, API keys, anything saved in the UI).
#
# Flow data is NOT included: it is a rolling 30-day window and usually far
# larger than everything else. See README "Backup & restore" if you need it.
#
# Usage:
#   scripts/backup.sh [target-dir]        # default: ./backups
# Env:
#   KEEP   number of archives to keep (default 14)
# Cron example (daily 02:30):
#   30 2 * * * cd $HOME/goflow2-stack && scripts/backup.sh /mnt/backup/goflow2 >> backups/backup.log 2>&1

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TARGET="${1:-${ROOT}/backups}"
KEEP="${KEEP:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${TARGET}" "${WORK}/config"

for f in .env grafana/ldap.toml alertmanager/alertmanager.yml; do
  if [[ -f "${f}" ]]; then
    mkdir -p "${WORK}/config/$(dirname "${f}")"
    cp -p "${f}" "${WORK}/config/${f}"
  fi
done

# Grafana database, read through the running container (works without sudo
# and whatever the compose project name is).
GRAFANA_ID="$(docker compose ps -q grafana)"
[[ -n "${GRAFANA_ID}" ]] || { echo "[backup] ERROR: grafana container not running" >&2; exit 1; }
docker cp "${GRAFANA_ID}:/var/lib/grafana/grafana.db" "${WORK}/grafana.db"

OUT="${TARGET}/goflow2-stack-${STAMP}.tar.gz"
( umask 077; tar -C "${WORK}" -czf "${OUT}" . )
echo "[backup] wrote ${OUT} ($(du -h "${OUT}" | cut -f1))"

# Retention
ls -1t "${TARGET}"/goflow2-stack-*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | while read -r old; do
  rm -f -- "${old}"
  echo "[backup] removed old archive ${old}"
done
