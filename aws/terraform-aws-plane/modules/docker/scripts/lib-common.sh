#!/usr/bin/env bash
# lib-common.sh: the cloud-neutral part of Plane's Docker mode converge. Sourced by plane-converge.sh.
#
# Same on every cloud. The cloud library (lib-aws.sh here) provides:
#   ensure_cli                       install the CLI the functions below need
#   fetch_secret <id>                print a secret's JSON object (plane.env key -> value) on stdout
#   fetch_object <url> <dest>        download an asset from a non-https URL (s3://, gs://, ...)
#   data_device                      print the data volume's block device path
#   upload_backup <file|-> <key>     store one backup object
#   sync_backup <dir> <prefix>       mirror a directory into the backups store
#
# Configuration comes from /etc/plane/plane.conf (written by the SSM document): PLANE_DOMAIN, PLANE_VERSION,
# ASSETS_URL, ASSETS_SHA256_COMPOSE, ASSETS_SHA256_VARIABLES, DOCKER_VERSION, COMPOSE_VERSION,
# APP_KEYS_SECRET, BUNDLED_SECRET, WEB_CERT_SECRET, EMAIL_CERT_SECRET, SETUP_TIMEOUT_SECONDS.

PLANE_DIR=${PLANE_DIR:-/opt/plane}
PLANE_STATE_DIR="$PLANE_DIR/.plane"
PLANE_CONF_DIR=${PLANE_CONF_DIR:-/etc/plane}
COMPOSE_PROJECT=plane

# Keys that must hold a generated value in plane.env: never empty, never the value Plane's variables.env ships.
PLANE_SECRET_KEYS=(
  SECRET_KEY AES_SECRET_KEY SILO_HMAC_SECRET_KEY LIVE_SERVER_SECRET_KEY PI_INTERNAL_SECRET CURSOR_WEBHOOK_SECRET
  WEBHOOK_SECRET MACHINE_SIGNATURE POSTGRES_PASSWORD DATABASE_URL FOLLOWER_POSTGRES_URI PLANE_PI_DATABASE_URL
  RABBITMQ_PASSWORD RABBITMQ_DEFAULT_PASS AMQP_URL MINIO_ROOT_USER MINIO_ROOT_PASSWORD AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
)

log() { printf '%s plane: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

# retry <attempts> <delay seconds> <command...>
retry() {
  local attempts=$1 delay=$2 i
  shift 2
  for ((i = 1; i <= attempts; i++)); do
    "$@" && return 0
    if ((i < attempts)); then
      log "attempt $i/$attempts failed, retrying in ${delay}s: $*"
      sleep "$delay"
    fi
  done
  return 1
}

# docker compose on the installed stack.
compose() {
  docker compose -p "$COMPOSE_PROJECT" --project-directory "$PLANE_DIR" \
    -f "$PLANE_DIR/docker-compose.yml" --env-file "$PLANE_DIR/plane.env" "$@"
}

apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -q "$@"
}

# ensure_packages <package...>: install what's missing.
ensure_packages() {
  local missing=() p
  for p in "$@"; do
    # shellcheck disable=SC2016 # ${Status} is dpkg-query's format, not a shell expansion
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing+=("$p")
  done
  ((${#missing[@]} == 0)) && return 0
  retry 3 10 apt_get update
  retry 3 10 apt_get install -y --no-install-recommends "${missing[@]}"
}

# The first boot's cloud-init (and its apt runs) must finish before the converge installs packages.
wait_for_boot() {
  if command -v cloud-init >/dev/null 2>&1; then
    timeout 900 cloud-init status --wait >/dev/null 2>&1 || log "cloud-init didn't report done; continuing"
  fi
}

# Format (only when blank), mount and grow the data volume at $PLANE_DIR.
ensure_data_volume() {
  local dev deadline=$((SECONDS + 600)) fstype uuid rc=0
  dev=$(data_device)
  until [ -b "$dev" ]; do
    ((SECONDS < deadline)) || die "data volume ($dev) isn't attached after 10 minutes"
    sleep 5
  done
  dev=$(readlink -f "$dev")

  # blkid -p exits 2 only when the device has no signature at all: only then is it a new, empty volume.
  blkid -p "$dev" >/dev/null 2>&1 || rc=$?
  if ((rc == 2)); then
    log "formatting the new data volume $dev (ext4)"
    mkfs.ext4 -q -L plane-data "$dev"
  elif ((rc != 0)); then
    die "can't probe $dev (blkid exit $rc); refusing to format it"
  fi
  fstype=$(blkid -o value -s TYPE "$dev")
  [ "$fstype" = ext4 ] || die "the data volume $dev holds $fstype, expected ext4"

  uuid=$(blkid -o value -s UUID "$dev")
  if ! grep -q "^UUID=$uuid $PLANE_DIR " /etc/fstab; then
    sed -i "\\|[[:space:]]${PLANE_DIR}[[:space:]]|d" /etc/fstab
    echo "UUID=$uuid $PLANE_DIR ext4 defaults,nofail,x-systemd.device-timeout=5min 0 2" >>/etc/fstab
    systemctl daemon-reload
  fi
  install -d -m 0700 "$PLANE_DIR"
  mountpoint -q "$PLANE_DIR" || mount "$PLANE_DIR"
  mountpoint -q "$PLANE_DIR" || die "$PLANE_DIR isn't mounted"
  # Online grow after data_volume_gb was raised; a no-op otherwise.
  resize2fs "$dev" >/dev/null 2>&1 || log "resize2fs on $dev failed; continuing"
  chmod 0700 "$PLANE_DIR"
  install -d -m 0700 "$PLANE_STATE_DIR"
}

# The domain is the licence identity; migrations can't be undone.
check_identity() {
  local current
  if [ -f "$PLANE_STATE_DIR/domain" ]; then
    current=$(<"$PLANE_STATE_DIR/domain")
    [ "$current" = "$PLANE_DOMAIN" ] ||
      die "this data volume belongs to $current; the domain can't change (requested $PLANE_DOMAIN)"
  fi
  if [ -f "$PLANE_STATE_DIR/version" ]; then
    current=$(<"$PLANE_STATE_DIR/version")
    if [ "$current" != "$PLANE_VERSION" ] &&
      [ "$(printf '%s\n%s\n' "$current" "$PLANE_VERSION" | sort -V | tail -n 1)" = "$current" ]; then
      die "Plane $current is installed; downgrading to $PLANE_VERSION isn't supported"
    fi
  fi
}

# apt_version <package> <version or prefix>: the newest matching version in the apt cache.
apt_version() {
  apt-cache madison "$1" | awk -v p="$2" '{
    v = $3
    if (index(v, p) == 1) { n = substr(v, length(p) + 1, 1); if (n == "" || n == "." || n == "-" || n == "~") print v }
  }' | sort -V | tail -n 1
}

write_if_changed() { # write_if_changed <file> <mode> < content; returns 0 when the file changed
  local tmp
  tmp=$(mktemp "$1.XXXXXX")
  cat >"$tmp"
  chmod "$2" "$tmp"
  if [ -f "$1" ] && cmp -s "$tmp" "$1"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$1"
}

# ensure_docker <engine version|prefix> <compose plugin version|prefix>: Docker's apt repository, pinned and held.
ensure_docker() {
  local engine=$1 plugin=$2 arch codename key=/etc/apt/keyrings/docker.asc
  local list=/etc/apt/sources.list.d/docker.list want_engine want_compose have_engine have_compose
  ensure_packages ca-certificates curl jq
  arch=$(dpkg --print-architecture)
  # shellcheck disable=SC1091 # os-release exists on every supported image
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")

  if [ ! -s "$key" ]; then
    install -d -m 0755 /etc/apt/keyrings
    retry 3 10 curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$key"
    chmod a+r "$key"
  fi
  if echo "deb [arch=$arch signed-by=$key] https://download.docker.com/linux/ubuntu $codename stable" |
    write_if_changed "$list" 0644 || [ -z "$(apt_version docker-ce "5:$engine")" ]; then
    retry 3 10 apt_get update
  fi

  want_engine=$(apt_version docker-ce "5:$engine")
  want_compose=$(apt_version docker-compose-plugin "$plugin")
  [ -n "$want_engine" ] || die "Docker Engine $engine isn't in Docker's apt repository (docker.docker_version)"
  [ -n "$want_compose" ] || die "Compose $plugin isn't in Docker's apt repository (docker.compose_version)"
  have_engine=$(dpkg-query -W -f='${Version}' docker-ce 2>/dev/null || true)
  have_compose=$(dpkg-query -W -f='${Version}' docker-compose-plugin 2>/dev/null || true)
  if [ "$have_engine" != "$want_engine" ] || [ "$have_compose" != "$want_compose" ]; then
    log "installing Docker Engine $want_engine and Compose $want_compose"
    retry 3 10 apt_get install -y --allow-downgrades --allow-change-held-packages \
      "docker-ce=$want_engine" "docker-ce-cli=$want_engine" containerd.io "docker-compose-plugin=$want_compose"
    apt-mark hold docker-ce docker-ce-cli docker-compose-plugin >/dev/null
  fi

  # Containers start only once the data volume is mounted (a missing volume must not mean an empty Plane).
  install -d -m 0755 /etc/systemd/system/docker.service.d
  local reload=1 restart=1
  printf '[Unit]\nRequiresMountsFor=%s\n' "$PLANE_DIR" |
    write_if_changed /etc/systemd/system/docker.service.d/plane.conf 0644 && reload=0
  install -d -m 0755 /etc/docker
  printf '{\n  "log-driver": "local",\n  "log-opts": { "max-size": "20m", "max-file": "5" }\n}\n' |
    write_if_changed /etc/docker/daemon.json 0644 && restart=0
  ((reload == 0)) && systemctl daemon-reload
  systemctl enable --now docker >/dev/null
  if ((restart == 0)); then systemctl restart docker; fi
  docker compose version >/dev/null || die "the Docker Compose plugin doesn't run"
}

asset_sha256() {
  case $1 in
  docker-compose.yml) printf '%s' "$ASSETS_SHA256_COMPOSE" ;;
  variables.env) printf '%s' "$ASSETS_SHA256_VARIABLES" ;;
  esac
}

# Download this release's docker-compose.yml and variables.env into $PLANE_DIR/releases/<version>/.
fetch_assets() {
  local dir="$PLANE_DIR/releases/$PLANE_VERSION" f url tmp sum
  install -d -m 0700 "$PLANE_DIR/releases" "$dir"
  find "$dir" -maxdepth 1 -type f -name '.*' -delete # partial downloads of a failed run
  for f in docker-compose.yml variables.env; do
    sum=$(asset_sha256 "$f")
    if [ -s "$dir/$f" ] && { [ -z "$sum" ] || echo "$sum  $dir/$f" | sha256sum -c --quiet - >/dev/null 2>&1; }; then
      continue
    fi
    url="${ASSETS_URL%/}/$PLANE_VERSION/$f"
    tmp=$(mktemp "$dir/.$f.XXXXXX")
    case $url in
    https://*) retry 3 10 curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp" "$url" || die "can't download $url" ;;
    *) retry 3 10 fetch_object "$url" "$tmp" || die "can't download $url" ;;
    esac
    if [ -n "$sum" ]; then
      echo "$sum  $tmp" | sha256sum -c --quiet - || die "$url doesn't match docker.compose_assets_sha256[\"$f\"]"
    fi
    if [ "$(tr -d '[:space:]' <"$tmp" | head -c 1)" = "<" ]; then
      die "$url returned HTML, not $f. Plane's public URL for the release assets isn't serving them yet (E20); set docker.compose_assets_url to where the files of $PLANE_VERSION are published."
    fi
    case $f in
    docker-compose.yml) grep -q '^services:' "$tmp" || die "$url isn't a Compose file (no top-level services:)" ;;
    variables.env) grep -q '^APP_RELEASE_VERSION=' "$tmp" || die "$url isn't Plane's variables.env" ;;
    esac
    mv -f "$tmp" "$dir/$f"
  done
}

# secrets_env <secret id...>: KEY=value lines from each secret's JSON object.
secrets_env() {
  local id
  for id in "$@"; do
    fetch_secret "$id" | jq -er 'to_entries[] | select(.value | type == "string") | select(.value | test("\n") | not) | "\(.key)=\(.value)"' ||
      die "can't read secret $id"
  done
}

# render_env <variables.env> <overrides>: variables.env with every override key replaced in place (single quotes:
# literal in Compose) and missing ones appended. Override lines are KEY=value; later lines win.
render_env() {
  awk -v q="'" '
    NR == FNR {
      if (match($0, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        k = substr($0, 1, RLENGTH - 1)
        if (!(k in val)) order[++n] = k
        val[k] = substr($0, RLENGTH + 1)
      }
      next
    }
    match($0, /^[A-Za-z_][A-Za-z0-9_]*=/) {
      k = substr($0, 1, RLENGTH - 1)
      if (k in val) {
        if (!(k in done)) print k "=" q val[k] q
        done[k] = 1
        next
      }
    }
    { print }
    END { for (i = 1; i <= n; i++) if (!(order[i] in done)) print order[i] "=" q val[order[i]] q }
  ' "$2" "$1"
}

env_value() { # env_value <file> <key>: the value, quotes stripped
  awk -v k="$2" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2); gsub(/^'"'"'|'"'"'$/, "", v); gsub(/^"|"$/, "", v); print v; exit }' "$1"
}

# assert_generated <rendered plane.env> <vendor variables.env>: no secret left empty or at Plane's shipped value.
assert_generated() {
  local k value shipped
  for k in "${PLANE_SECRET_KEYS[@]}"; do
    value=$(env_value "$1" "$k")
    shipped=$(env_value "$2" "$k")
    [ -n "$value" ] || die "plane.env has no value for $k"
    [ "$value" != "$shipped" ] || die "plane.env still has Plane's default $k"
  done
  ! grep -Eq "plane:plane@|=.?(access-key|secret-key).?$" "$1" || die "plane.env still has a default credential"
}

# sync_cert <secret id> <dir> <mode>: write cert.pem and key.pem from a secret with JSON keys "tls.crt" and
# "tls.key". Returns 0 when a file changed.
sync_cert() {
  local json changed=1
  json=$(fetch_secret "$1") || die "can't read certificate secret $1"
  jq -e 'has("tls.crt") and has("tls.key")' >/dev/null <<<"$json" ||
    die "certificate secret $1 needs JSON keys \"tls.crt\" and \"tls.key\""
  install -d -m 0755 "$2"
  jq -r '."tls.crt"' <<<"$json" | write_if_changed "$2/cert.pem" "$3" && changed=0
  jq -r '."tls.key"' <<<"$json" | write_if_changed "$2/key.pem" "$3" && changed=0
  return "$changed"
}

# Web certificate for Caddy (/opt/plane/ssl) and email certificate (/opt/plane/data/email/tls). The directories
# sit under $PLANE_DIR (0700), so the files can be readable by the containers' own users (email isn't root).
# Prints the services to restart.
sync_certs() {
  if [ -n "$WEB_CERT_SECRET" ] && sync_cert "$WEB_CERT_SECRET" "$PLANE_DIR/ssl" 0644; then echo proxy; fi
  if [ -n "$EMAIL_CERT_SECRET" ] && sync_cert "$EMAIL_CERT_SECRET" "$PLANE_DIR/data/email/tls" 0644; then echo email; fi
}

# Postgres dump of each Plane database to the backups store, under backups/postgres/<time>-<label>/.
backup_postgres() {
  local label=$1 ts db
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  if [ -z "$(compose ps --status running -q plane-db 2>/dev/null)" ]; then
    log "plane-db isn't running; no database dump"
    return 0
  fi
  for db in $(compose exec -T plane-db psql -U plane -d postgres -Atc \
    "SELECT datname FROM pg_database WHERE datname IN ('plane', 'plane_pi')"); do
    log "dumping database $db"
    compose exec -T plane-db pg_dump -U plane -Fc "$db" | upload_backup - "backups/postgres/$ts-$label/$db.dump"
  done
}

# Mirror of MinIO's data directory (restore: stop the stack, sync it back to the same path, start).
backup_minio() {
  [ -d "$PLANE_DIR/data/minio/uploads" ] || return 0
  log "mirroring MinIO data"
  sync_backup "$PLANE_DIR/data/minio/uploads" "backups/minio/uploads"
}

# The services to run: those not scaled to zero.
active_services() {
  compose config --format json | jq -r '.services | to_entries[] | select((.value.deploy.replicas // 1) > 0) | .key'
}

# Wait for migrations, the api and the proxy.
wait_healthy() {
  local timeout=$1 deadline migrator state api_ok code c
  deadline=$((SECONDS + timeout))
  while :; do
    migrator=$(compose ps -a -q migrator)
    state=$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$migrator" 2>/dev/null || echo "missing -")
    case $state in
    "exited 0") ;;
    exited*)
      compose logs --no-color --tail 200 migrator >&2 || true
      die "database migrations failed ($state)"
      ;;
    esac

    api_ok=1
    [ -n "$(compose ps -q api)" ] || api_ok=0
    for c in $(compose ps -q api); do
      [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c")" = healthy ] || api_ok=0
    done
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -H "Host: $PLANE_DOMAIN" http://127.0.0.1/ || true)

    if [ "$state" = "exited 0" ] && ((api_ok)) && [[ $code =~ ^[23] ]]; then
      log "Plane $PLANE_VERSION is up"
      return 0
    fi
    if ((SECONDS >= deadline)); then
      compose ps -a >&2 || true
      compose logs --no-color --tail 100 migrator api proxy >&2 || true
      die "not healthy after ${timeout}s (migrator: $state, api healthy: $api_ok, proxy HTTP: $code)"
    fi
    sleep 10
  done
}
