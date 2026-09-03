#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  echo "Usage: $0 <domain>  (e.g. ./deploy-ec2.sh dreamhighpublicschool.in)" >&2
  exit 1
fi
if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid domain: $DOMAIN" >&2
  exit 1
fi

APP_DIR="${APP_DIR:-/home/ec2-user/DPS}"
APP_USER="${APP_USER:-ec2-user}"
SERVICE_NAME="dreamhigh"
NODE_MAJOR="22"
NVM_VERSION="v0.40.3"

log() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$1"
}

if [[ ! -f "$APP_DIR/package.json" ]]; then
  echo "package.json was not found in $APP_DIR" >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to install system packages and configure services." >&2
  exit 1
fi

log "Installing operating-system packages"
if command -v dnf >/dev/null 2>&1; then
  # Amazon Linux 2023 includes curl-minimal, which provides the curl command
  # and intentionally conflicts with the separate full curl package.
  sudo dnf install -y git tar gzip xz nginx
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y git tar gzip xz nginx
else
  echo "This script expects Amazon Linux with dnf or yum." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but was not provided by the operating system." >&2
  exit 1
fi

export NVM_DIR="/home/$APP_USER/.nvm"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  log "Installing NVM for $APP_USER"
  sudo -u "$APP_USER" env HOME="/home/$APP_USER" bash -c \
    "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"
fi

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

log "Installing and selecting Node.js $NODE_MAJOR"
nvm install "$NODE_MAJOR"
nvm alias default "$NODE_MAJOR"
nvm use "$NODE_MAJOR"

NODE_BIN="$(dirname "$(command -v node)")"
NPM_BIN="$(command -v npm)"

log "Installing project dependencies"
sudo chown -R "$APP_USER:$APP_USER" "$APP_DIR"
cd "$APP_DIR"
sudo -u "$APP_USER" env \
  HOME="/home/$APP_USER" \
  PATH="$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "$NPM_BIN" ci

log "Building the production application"
sudo -u "$APP_USER" env \
  HOME="/home/$APP_USER" \
  NODE_ENV=production \
  PATH="$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "$NPM_BIN" run build

log "Creating the systemd service"
sudo tee "/etc/systemd/system/$SERVICE_NAME.service" >/dev/null <<EOF
[Unit]
Description=DreamHigh Public School website
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=PATH=$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$NPM_BIN start
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

log "Configuring Nginx"
sudo tee /etc/nginx/conf.d/dreamhigh.conf >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

if command -v setsebool >/dev/null 2>&1; then
  sudo setsebool -P httpd_can_network_connect 1 || true
fi

sudo nginx -t

log "Starting the website and Nginx"
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME"
sudo systemctl enable --now nginx
sudo systemctl restart "$SERVICE_NAME"
sudo systemctl reload nginx

log "Checking the local website response"
for attempt in {1..15}; do
  if curl -fsS http://127.0.0.1:3000/ >/dev/null 2>&1; then
    echo "DreamHigh is running successfully."
    echo "Open: http://$DOMAIN"
    echo "Add HTTPS with: sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN"
    exit 0
  fi
  sleep 2
done

echo "The service did not respond within 30 seconds." >&2
sudo systemctl --no-pager --full status "$SERVICE_NAME" || true
sudo journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
exit 1
