#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy pre-built DPS app to EC2 — no npm install or build on the server.
# Usage: ./deploy-prebuilt.sh <ec2-host> [ssh-key-path]
# Example: ./deploy-prebuilt.sh 65.1.106.3 ~/.ssh/dreamhigh.pem

HOST="${1:-}"
KEY="${2:-}"
REMOTE_USER="ec2-user"
REMOTE_DIR="/home/ec2-user/DPS"
SERVICE_NAME="dreamhigh"

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <ec2-host> [ssh-key-path]"
  echo "Example: $0 65.1.106.3 ~/.ssh/dreamhigh.pem"
  exit 1
fi

SSH_OPTS=""
if [[ -n "$KEY" ]]; then
  SSH_OPTS="-i $KEY"
fi

echo "==> Building locally..."
npm run build

echo "==> Creating deployment tarball..."
TARBALL="/tmp/dps-deploy.tar.gz"
tar -czf "$TARBALL" \
  dist/ \
  node_modules/ \
  public/ \
  package.json

SIZE=$(du -sh "$TARBALL" | cut -f1)
echo "==> Tarball size: $SIZE"

echo "==> Uploading to $HOST..."
scp $SSH_OPTS "$TARBALL" "$REMOTE_USER@$HOST:/tmp/dps-deploy.tar.gz"

echo "==> Extracting and restarting on server..."
ssh $SSH_OPTS "$REMOTE_USER@$HOST" bash -s <<EOF
set -e
echo "  Stopping service..."
sudo systemctl stop $SERVICE_NAME 2>/dev/null || true

echo "  Backing up current deployment..."
mv $REMOTE_DIR ${REMOTE_DIR}.backup.\$(date +%s) 2>/dev/null || true

echo "  Creating fresh directory..."
mkdir -p $REMOTE_DIR

echo "  Extracting..."
tar -xzf /tmp/dps-deploy.tar.gz -C $REMOTE_DIR
rm /tmp/dps-deploy.tar.gz

echo "  Updating systemd service to run node directly..."
sudo tee /etc/systemd/system/$SERVICE_NAME.service >/dev/null <<SVC
[Unit]
Description=DreamHigh Public School website
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=$REMOTE_DIR
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=PATH=/home/ec2-user/.nvm/versions/node/v22.23.2/bin:/home/ec2-user/DPS/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/home/ec2-user/.nvm/versions/node/v22.23.2/bin/npm start
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
SVC
sudo systemctl daemon-reload

echo "  Starting service..."
sudo systemctl restart $SERVICE_NAME

echo "  Waiting for app to start..."
for i in \$(seq 1 15); do
  if curl -fsS http://127.0.0.1:3000/ >/dev/null 2>&1; then
    echo "  DreamHigh is running!"
    curl -s -o /dev/null -w "  HTTP status: %{http_code}\n" http://127.0.0.1:3000/
    exit 0
  fi
  sleep 2
done

echo "  Service did not respond in 30 seconds."
sudo journalctl -u $SERVICE_NAME -n 20 --no-pager
exit 1
EOF

echo "==> Done!"
