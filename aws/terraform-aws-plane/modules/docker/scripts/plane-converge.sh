#!/usr/bin/env bash
# plane-converge.sh <converge|backup|certs>: run by SSM as root (see ssm.tf). Idempotent.
#   converge  bring the instance to the configured state: data volume, Docker, compose assets, plane.env, stack
#   backup    pg_dump of Plane's databases and a mirror of MinIO's data to the backups store
#   certs     copy your certificates from the secrets store; restart the services using them
set -euo pipefail
set +x # the output is stored (SSM): never trace commands that handle secrets
umask 077
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/snap/bin"

LIB_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=SCRIPTDIR/lib-common.sh
. "$LIB_DIR/lib-common.sh"
# shellcheck source=SCRIPTDIR/lib-aws.sh
. "$LIB_DIR/lib-aws.sh"
# shellcheck source=/dev/null
. "$PLANE_CONF_DIR/plane.conf"

mode=${1:-converge}
install -d -m 0700 /var/log/plane
exec > >(tee -a "/var/log/plane/$mode.log") 2>&1

# Converge, backup and certs never overlap.
exec 9>/run/plane.lock
flock -w "${SETUP_TIMEOUT_SECONDS:-3600}" 9 || die "another Plane job holds /run/plane.lock"

converge() {
  local release previous="" restart
  wait_for_boot
  ensure_data_volume
  check_identity
  ensure_docker "$DOCKER_VERSION" "$COMPOSE_VERSION"
  ensure_cli
  fetch_assets
  release="$PLANE_DIR/releases/$PLANE_VERSION"
  restart=$(sync_certs)

  # plane.env = Plane's variables.env + the module's settings + the generated secrets (later lines win).
  # Globals, so the EXIT trap can remove them.
  overrides=$(mktemp /run/plane-overrides.XXXXXX)
  new_env=$(mktemp "$PLANE_DIR/.plane.env.XXXXXX")
  trap 'rm -f "$overrides" "$new_env"' EXIT
  {
    cat "$PLANE_CONF_DIR/managed.env"
    secrets_env "$APP_KEYS_SECRET" "$BUNDLED_SECRET"
  } >"$overrides"
  render_env "$release/variables.env" "$overrides" >"$new_env"
  rm -f "$overrides"
  assert_generated "$new_env" "$release/variables.env"
  docker compose -p "$COMPOSE_PROJECT" --project-directory "$PLANE_DIR" -f "$release/docker-compose.yml" \
    --env-file "$new_env" config -q || die "the rendered Compose configuration is invalid"

  # Upgrade: a database dump first (the DLM snapshots are the other safety net).
  [ -f "$PLANE_STATE_DIR/version" ] && previous=$(<"$PLANE_STATE_DIR/version")
  if [ -n "$previous" ] && [ "$previous" != "$PLANE_VERSION" ] && [ -f "$PLANE_DIR/docker-compose.yml" ]; then
    log "upgrading Plane $previous -> $PLANE_VERSION"
    backup_postgres "pre-upgrade-$previous-to-$PLANE_VERSION"
  fi

  install -m 0600 "$release/docker-compose.yml" "$PLANE_DIR/docker-compose.yml"
  mv -f "$new_env" "$PLANE_DIR/plane.env"
  chmod 0600 "$PLANE_DIR/plane.env"

  # Pull before touching the running stack, so a registry outage leaves it as it was.
  mapfile -t services < <(active_services)
  retry 3 30 compose pull --quiet "${services[@]}" || die "can't pull Plane's images"
  compose up -d --remove-orphans
  if [ -n "$restart" ]; then
    # shellcheck disable=SC2086 # one service name per word
    compose restart $restart
  fi
  wait_healthy "${SETUP_TIMEOUT_SECONDS:-3600}"

  echo "$PLANE_DOMAIN" >"$PLANE_STATE_DIR/domain"
  echo "$PLANE_VERSION" >"$PLANE_STATE_DIR/version"
}

backup() {
  [ -f "$PLANE_DIR/docker-compose.yml" ] || {
    log "Plane isn't installed yet; nothing to back up"
    return 0
  }
  ensure_cli
  backup_postgres nightly
  backup_minio
  log "backup done"
}

certs() {
  local restart
  [ -f "$PLANE_DIR/docker-compose.yml" ] || {
    log "Plane isn't installed yet; the converge copies the certificates"
    return 0
  }
  ensure_cli
  restart=$(sync_certs)
  if [ -n "$restart" ]; then
    log "certificates changed; restarting $restart"
    # shellcheck disable=SC2086 # one service name per word
    compose restart $restart
  else
    log "certificates unchanged"
  fi
}

case $mode in
converge | backup | certs) "$mode" ;;
*) die "unknown mode: $mode (converge, backup or certs)" ;;
esac
