#!/usr/bin/env bash
# Deploy Mailu for getserviceflow.app, locally (OrbStack/Docker Desktop) or on a production server.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOMAIN=${DOMAIN:-getserviceflow.app}
MODE="" ; CMD=up ; VERBOSE=0 ; LOGFILE="" ; ASSUME_YES=0 ; TZ_VALUE=${TZ_VALUE:-} ; ADMIN_PASSWORD=${ADMIN_PASSWORD:-}
SERVICE_ARGS=() ; CMD_SET=0

usage() {
  cat <<USAGE
Usage: $0 (--local | --prod) [options] [command] [service...]

Mode (required):
  --local            Test deployment on this machine (OrbStack/Docker). HTTP only, no Let's Encrypt.
                     Data in $HERE/.local (git-ignored).
  --prod             Production deployment on a server. Let's Encrypt TLS, data in /mailu. Needs root.

Options:
  -v, --verbose      Verbose output (bash trace + docker compose --verbose)
  --log FILE         Also write all output to FILE
  --domain NAME      Mail domain (default: $DOMAIN); mail host is mail.NAME in --prod, localhost in --local
  --tz ZONE          Timezone, e.g. Asia/Kolkata (default: auto-detected from this machine, else UTC)
  --password PASS    Admin password (default: random, printed once)
  -y, --yes          Don't ask for confirmation (for 'reset')
  -h, --help         Show this help

Commands (default: up):
  up        Create config if missing, start the stack, create admin@DOMAIN
  down      Stop containers (data kept)
  status    Show container state
  logs      Follow logs (optionally name services: front smtp imap admin ...)
  pull      Pull newer images and restart
  cli ARGS  Run "flask mailu ARGS" in the admin container (user, alias, domain, ...). Put options before "cli".
  reset     --local only: stop and DELETE all local data

Examples:
  $0 --local                  # first local run
  $0 --local -v --log run.log up
  $0 --local logs smtp
  $0 --prod                   # on the server, as root
USAGE
}

while [ $# -gt 0 ]; do
  if [ "$CMD" = cli ] && [ "$CMD_SET" = 1 ]; then SERVICE_ARGS+=("$1"); shift; continue; fi
  case $1 in
    --local) MODE=local ;;
    --prod) MODE=prod ;;
    -v|--verbose) VERBOSE=1 ;;
    --log) [ $# -ge 2 ] || { echo "--log needs a file"; exit 2; }; LOGFILE=$2; shift ;;
    --domain) [ $# -ge 2 ] || { echo "--domain needs a value"; exit 2; }; DOMAIN=$2; shift ;;
    --tz) [ $# -ge 2 ] || { echo "--tz needs a value"; exit 2; }; TZ_VALUE=$2; shift ;;
    --password) [ $# -ge 2 ] || { echo "--password needs a value"; exit 2; }; ADMIN_PASSWORD=$2; shift ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    up|down|status|logs|pull|reset|cli) if [ "$CMD_SET" = 0 ]; then CMD=$1; CMD_SET=1; else SERVICE_ARGS+=("$1"); fi ;;
    -*) echo "Unknown option: $1"; usage; exit 2 ;;
    *) if [ "$CMD_SET" = 1 ]; then SERVICE_ARGS+=("$1"); else echo "Unknown command: $1"; usage; exit 2; fi ;;
  esac
  shift
done
[ -n "$MODE" ] || { echo "Choose --local or --prod"; usage; exit 2; }

if [ -n "$LOGFILE" ]; then
  mkdir -p "$(dirname "$LOGFILE")"
  exec > >(tee -a "$LOGFILE") 2>&1
  echo "=== $(date -u +%FT%TZ) deploy.sh $MODE $CMD ==="
fi
[ "$VERBOSE" = 1 ] && set -x

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$MODE" = prod ]; then
  ROOT=${ROOT:-/mailu}; HOST=mail.$DOMAIN; TLS=letsencrypt; SCHEME=https
  [ "$(id -u)" = 0 ] || die "--prod must run as root"
else
  ROOT=${ROOT:-$HERE/.local}; HOST=localhost; TLS=notls; SCHEME=http
fi

COMPOSE=(docker compose --project-directory "$ROOT")
[ "$VERBOSE" = 1 ] && COMPOSE+=(--verbose)

detect_tz() {
  local z=""
  if [ -L /etc/localtime ]; then z=$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')
  elif command -v timedatectl >/dev/null; then z=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  elif [ -f /etc/timezone ]; then z=$(cat /etc/timezone); fi
  case $z in */*|UTC|Etc/*) echo "$z" ;; *) echo "Etc/UTC" ;; esac
}

ensure_docker() {
  if ! command -v docker >/dev/null; then
    [ "$MODE" = prod ] || die "docker not found. Install OrbStack (https://orbstack.dev) and make sure 'docker' is on PATH."
    log "Installing Docker"; curl -fsSL https://get.docker.com | sh
  fi
  docker compose version >/dev/null 2>&1 || die "'docker compose' plugin missing"
  docker info >/dev/null 2>&1 || die "Docker daemon not running (start OrbStack?)"
}

port_in_use() {
  if command -v lsof >/dev/null; then lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v ss >/dev/null; then ss -ltn "( sport = :$1 )" | grep -q LISTEN
  else return 1; fi
}

check_ports() {
  local busy=() p
  for p in "${PORTS[@]}"; do port_in_use "$p" && busy+=("$p"); done
  if [ ${#busy[@]} -gt 0 ]; then
    # Ignore ports held by our own running stack
    if "${COMPOSE[@]}" ps -q front 2>/dev/null | grep -q .; then return 0; fi
    die "Ports in use: ${busy[*]}. Stop whatever holds them (for --local, set PORT_HTTP, PORT_SMTP, ... in $ROOT/.env)."
  fi
}

write_config() {
  mkdir -p "$ROOT"/{certs,data,dkim,mail,mailqueue,filter,redis,webmail,overrides}
  cp "$HERE/docker-compose.yml" "$ROOT/docker-compose.yml"
  if [ ! -f "$ROOT/.env" ]; then echo "ROOT=$ROOT" > "$ROOT/.env"; fi
  if [ ! -f "$ROOT/mailu.env" ]; then
    log "Generating $ROOT/mailu.env"
    sed -e "s/__SECRET_KEY__/$(openssl rand -hex 16 | tr a-f A-F)/" \
        -e "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" \
        -e "s/^HOSTNAMES=.*/HOSTNAMES=$HOST/" \
        -e "s/^TLS_FLAVOR=.*/TLS_FLAVOR=$TLS/" \
        -e "s#^TZ=.*#TZ=${TZ_VALUE:-$(detect_tz)}#" \
        -e "s#^WEBSITE=.*#WEBSITE=https://$DOMAIN#" \
        "$HERE/mailu.env.template" > "$ROOT/mailu.env"
    chmod 600 "$ROOT/mailu.env"
  else
    log "Keeping existing $ROOT/mailu.env (timezone: $(grep '^TZ=' "$ROOT/mailu.env" | cut -d= -f2); edit TZ there to change)"
  fi
}

# Host ports published by 'front' (honours PORT_* overrides from env or $ROOT/.env)
load_ports() {
  local f=$ROOT/.env
  [ -f "$f" ] && set -a && . "$f" && set +a
  PORTS=("${PORT_HTTP:-80}" "${PORT_HTTPS:-443}" "${PORT_SMTP:-25}" "${PORT_SMTPS:-465}" "${PORT_SUBMISSION:-587}"
         "${PORT_POP3:-110}" "${PORT_POP3S:-995}" "${PORT_IMAP:-143}" "${PORT_IMAPS:-993}" "${PORT_SIEVE:-4190}")
}

create_admin() {
  local pw=${ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)} ok=0 i
  log "Waiting for admin service (first start can take a minute or two)"
  for i in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T admin flask mailu admin admin "$DOMAIN" "$pw" --mode update >/dev/null 2>&1; then ok=1; break; fi
    sleep 5
  done
  [ $ok = 1 ] || die "Admin service never became ready. Run: $0 --$MODE logs admin"
  echo "  Admin login: admin@$DOMAIN"
  echo "  Password:    $pw"
  if [ "$MODE" = local ]; then
    ( umask 077; echo "admin@$DOMAIN $pw" > "$ROOT/admin-credentials.txt" )
    echo "  (saved to $ROOT/admin-credentials.txt)"
  fi
}

summary() {
  local port=${PORT_HTTP:-80} base="$SCHEME://$HOST"
  [ "$MODE" = local ] && [ "$port" != 80 ] && base="$base:$port"
  cat <<MSG

Mailu is up.
  Admin:   $base/admin
  Webmail: $base/webmail
MSG
  if [ "$MODE" = local ]; then
    cat <<MSG

Local testing notes:
  * Create users in the admin UI, then send between local users via webmail.
  * IMAP/SMTP clients: host localhost, SMTP port ${PORT_SUBMISSION:-587} (STARTTLS unavailable without TLS; use plain for testing only).
  * Outbound/inbound internet mail does NOT work locally (no public DNS/MX/PTR).
  * Stop: $0 --local down    Wipe: $0 --local reset
MSG
  else
    echo "Next: add DNS records (see ../INSTRUCTIONS.md): MX, SPF, DKIM (admin UI -> Mail domains -> Details), DMARC, PTR."
  fi
}

ensure_docker
case $CMD in
  up)
    write_config; load_ports; check_ports
    log "Starting stack ($MODE) in $ROOT"
    "${COMPOSE[@]}" up -d
    create_admin; summary ;;
  down)   "${COMPOSE[@]}" down ;;
  status) "${COMPOSE[@]}" ps ;;
  logs)   "${COMPOSE[@]}" logs -f --tail=100 ${SERVICE_ARGS[@]+"${SERVICE_ARGS[@]}"} ;;
  cli)    "${COMPOSE[@]}" exec -T admin flask mailu ${SERVICE_ARGS[@]+"${SERVICE_ARGS[@]}"} ;;
  pull)   "${COMPOSE[@]}" pull && "${COMPOSE[@]}" up -d ;;
  reset)
    [ "$MODE" = local ] || die "reset is only allowed with --local"
    if [ "$ASSUME_YES" != 1 ]; then read -r -p "Delete ALL local Mailu data in $ROOT? [y/N] " a; [ "$a" = y ] || exit 1; fi
    "${COMPOSE[@]}" down -v 2>/dev/null || true
    rm -rf "$ROOT"; log "Local data removed" ;;
esac
