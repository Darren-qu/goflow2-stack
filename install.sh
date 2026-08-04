#!/usr/bin/env bash
# Bootstrap from GitHub → run deploy.sh
#
# Usage (after you push this repo):
#   curl -fsSL https://raw.githubusercontent.com/<user>/goflow2-stack/main/install.sh | bash
#   # or
#   REPO_URL=https://github.com/<user>/goflow2-stack.git bash install.sh
#
# Env:
#   REPO_URL     git clone URL (edit default below before first publish)
#   BRANCH       default: main
#   INSTALL_DIR  default: $HOME/goflow2-stack
#   WITH_DOCKER  set to 1 to attempt Docker Engine install on Debian/Ubuntu
#   WITH_GEOIP   set to 1 to load GeoIP after stack is up

set -euo pipefail

# Default: internal Gitea (override with REPO_URL=...)
REPO_URL="${REPO_URL:-ssh://git@10.0.20.22:2222/netadmin/goflow2-stack.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/goflow2-stack}"
WITH_DOCKER="${WITH_DOCKER:-0}"
WITH_GEOIP="${WITH_GEOIP:-0}"

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_cmd git
need_cmd curl

if [[ "${WITH_DOCKER}" == "1" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    need_cmd sudo
    log "installing Docker Engine (Debian/Ubuntu)..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "${USER}" || true
    log "Docker installed. If 'docker' fails with permission denied, log out/in or use sudo."
  fi
fi

if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
  log "existing install at ${INSTALL_DIR} — pulling updates"
  git -C "${INSTALL_DIR}" fetch --depth 1 origin "${BRANCH}"
  git -C "${INSTALL_DIR}" checkout "${BRANCH}"
  git -C "${INSTALL_DIR}" pull --ff-only origin "${BRANCH}" || true
else
  log "cloning ${REPO_URL} (${BRANCH}) → ${INSTALL_DIR}"
  mkdir -p "$(dirname "${INSTALL_DIR}")"
  git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"
chmod +x deploy.sh install.sh clickhouse/setup_geoip.sh 2>/dev/null || true

ARGS=()
[[ "${WITH_GEOIP}" == "1" ]] && ARGS+=(--geoip)

log "running deploy.sh ${ARGS[*]:-}"
exec ./deploy.sh "${ARGS[@]}"
