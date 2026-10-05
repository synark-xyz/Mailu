#!/usr/bin/env bash
# Installs Mailu for getserviceflow.app on a fresh Debian/Ubuntu server. Run as root:
#   ./install.sh                 # first install
#   ADMIN_PASSWORD=... ./install.sh   # optionally choose the admin password (re-running resets it)
set -euo pipefail
ROOT=${ROOT:-/mailu}
DOMAIN=getserviceflow.app
HOST=mail.$DOMAIN
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "Run as root"; exit 1; }

command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
docker compose version >/dev/null

# Mail/web ports must be free.
for p in 25 80 443 587 993; do
  if ss -ltn "( sport = :$p )" | grep -q LISTEN; then
    echo "Port $p already in use - free it (stop apache/nginx/postfix) and re-run."; exit 1
  fi
done

mkdir -p "$ROOT"/{certs,data,dkim,mail,mailqueue,filter,redis,webmail,overrides}
cp "$HERE/docker-compose.yml" "$ROOT/docker-compose.yml"
echo "ROOT=$ROOT" > "$ROOT/.env"

if [ ! -f "$ROOT/mailu.env" ]; then
  sed "s/__SECRET_KEY__/$(openssl rand -hex 16 | tr a-f A-F)/" "$HERE/mailu.env.template" > "$ROOT/mailu.env"
  chmod 600 "$ROOT/mailu.env"
fi

cd "$ROOT"
docker compose up -d

ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(openssl rand -base64 18)}
echo "Waiting for admin service..."
for i in $(seq 1 60); do
  docker compose exec -T admin flask mailu admin admin "$DOMAIN" "$ADMIN_PASSWORD" --mode update >/dev/null 2>&1 && break
  sleep 5
done
echo "Admin login: admin@$DOMAIN  password: $ADMIN_PASSWORD  (change it after login)"

cat <<MSG

Mailu is up.
  Admin:   https://$HOST/admin   (login: admin@$DOMAIN)
  Webmail: https://$HOST/webmail
Next: add the DNS records from deploy/README.md (MX, SPF, DKIM, DMARC, PTR).
MSG
