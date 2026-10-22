#!/bin/sh
set -eu

cd "$(dirname "$0")"

env_value() {
  grep -E "^$1=" .env | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo ./deploy.sh" >&2; exit 1; }
[ -f .env ] || { echo ".env not found, copy .env.example" >&2; exit 1; }

DOMAIN=$(env_value DOMAIN | sed -E -e 's#^[a-z]+://##' -e 's#[/:].*$##')
EMAIL=$(env_value LETSENCRYPT_EMAIL)
[ -n "$DOMAIN" ] || { echo "DOMAIN is empty, check .env" >&2; exit 1; }

ROOT=/var/www/$DOMAIN
CERT_DIR=/etc/letsencrypt/live/$DOMAIN

if [ -d /etc/nginx/sites-available ]; then
  CONF=/etc/nginx/sites-available/$DOMAIN.conf
  LINK=/etc/nginx/sites-enabled/$DOMAIN.conf
else
  CONF=/etc/nginx/conf.d/$DOMAIN.conf
  LINK=
fi

mkdir -p "$ROOT"
rm -rf "$ROOT.new"
mkdir "$ROOT.new"
cp -R index.html screens "$ROOT.new/"
rm -rf "$ROOT.old"
mv "$ROOT" "$ROOT.old"
mv "$ROOT.new" "$ROOT"
rm -rf "$ROOT.old"

site_body() {
  cat <<CONF
    root $ROOT;
    index index.html;

    gzip on;
    gzip_types text/css application/javascript image/svg+xml;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /screens/ {
        expires 30d;
        add_header Cache-Control "public";
    }
CONF
}

write_http_conf() {
  {
    echo "server {"
    echo "    listen 80;"
    echo "    server_name $DOMAIN;"
    site_body
    echo "}"
  } > "$1"
}

write_https_conf() {
  {
    echo "server {"
    echo "    listen 443 ssl;"
    echo "    http2 on;"
    echo "    server_name $DOMAIN;"
    echo ""
    echo "    ssl_certificate $CERT_DIR/fullchain.pem;"
    echo "    ssl_certificate_key $CERT_DIR/privkey.pem;"
    [ -f /etc/letsencrypt/options-ssl-nginx.conf ] &&
      echo "    include /etc/letsencrypt/options-ssl-nginx.conf;"
    [ -f /etc/letsencrypt/ssl-dhparams.pem ] &&
      echo "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
    echo ""
    site_body
    echo "}"
    echo ""
    echo "server {"
    echo "    listen 80;"
    echo "    server_name $DOMAIN;"
    echo "    return 301 https://\$host\$request_uri;"
    echo "}"
  } > "$1"
}

install_conf() {
  [ -f "$CONF" ] && cp "$CONF" "$CONF.previous"
  cp "$1" "$CONF"
  [ -n "$LINK" ] && ln -sf "$CONF" "$LINK"

  if nginx -t 2>/dev/null; then
    systemctl reload nginx
  else
    nginx -t || true
    if [ -f "$CONF.previous" ]; then mv "$CONF.previous" "$CONF"; else rm -f "$CONF" ${LINK:+"$LINK"}; fi
    echo "nginx config is invalid, the previous one is kept" >&2
    exit 1
  fi
}

HOOK=/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
mkdir -p "$(dirname "$HOOK")"
printf '#!/bin/sh\nsystemctl reload nginx\n' > "$HOOK"
chmod +x "$HOOK"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
  write_http_conf "$TMP"
  install_conf "$TMP"
fi

if [ -n "$EMAIL" ]; then
  set -- --email "$EMAIL"
else
  set -- --register-unsafely-without-email
fi

if ! certbot certonly --nginx --non-interactive --agree-tos "$@" --keep-until-expiring \
  --cert-name "$DOMAIN" -d "$DOMAIN"; then
  [ -f "$CERT_DIR/fullchain.pem" ] || { echo "certbot failed, no certificate yet" >&2; exit 1; }
  echo "certbot failed, keeping the existing certificate" >&2
fi

write_https_conf "$TMP"
install_conf "$TMP"

echo "Done: https://$DOMAIN -> $ROOT"
