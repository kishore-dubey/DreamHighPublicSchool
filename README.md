# DreamHigh Public School Website

Website for DreamHigh Public School, Waraseoni, Madhya Pradesh. The application is built with Next.js/Vinext and requires Node.js 22.13 or newer.

## Local development

```powershell
npm ci
npm run dev
```

Create a production build with:

```powershell
npm run build
npm start
```

## Deploying to Amazon EC2

The repository includes two deployment helpers:

- [`upload-to-ec2.ps1`](./upload-to-ec2.ps1) runs on the local Windows computer. It packages and uploads the required application files using SCP.
- [`deploy-ec2.sh`](./deploy-ec2.sh) runs on the EC2 instance. It installs the server software, builds the application, and configures it as a service.

The scripts assume an Amazon Linux instance whose default user is `ec2-user`. The default application directory is `/home/ec2-user/DPS`.

### Prerequisites

On the Windows computer:

- The project repository and EC2 `.pem` private key.
- Windows PowerShell.
- Windows OpenSSH Client, providing `ssh.exe` and `scp.exe`.
- `tar.exe`, included with current Windows versions.

On AWS:

- A running Amazon Linux EC2 instance with a public IPv4 address or Elastic IP.
- The matching EC2 key pair.
- An inbound security-group rule allowing TCP port `22` from the administrator's public IP.
- An inbound security-group rule allowing TCP port `80` from visitors, normally `0.0.0.0/0` and `::/0`.
- An inbound security-group rule allowing TCP port `443` from visitors for HTTPS.

Port `3000` should not be opened publicly. Nginx connects to the application locally and exposes it through port `80`.

### Step 1: Upload the application

Open PowerShell in the project directory:

```powershell
cd C:\Users\your-user\path\to\DPS
```

If PowerShell prevents local scripts from running, allow them for only the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Run the uploader:

```powershell
.\upload-to-ec2.ps1 `
  -KeyPath "C:\path\to\your-key.pem" `
  -HostName "EC2_PUBLIC_IPV4"
```

For example:

```powershell
.\upload-to-ec2.ps1 `
  -KeyPath "C:\Users\kishore\Keys\dreamhigh.pem" `
  -HostName "203.0.113.10"
```

#### Upload-script parameters

| Parameter | Required | Default | Purpose |
| --- | --- | --- | --- |
| `KeyPath` | Yes | — | Full Windows path to the EC2 `.pem` key. |
| `HostName` | Yes | — | EC2 public IPv4 address or public DNS name. |
| `UserName` | No | `ec2-user` | SSH user on the instance. |
| `RemoteDirectory` | No | `/home/ec2-user/DPS` | Destination directory on EC2. |

If a different user or directory is required:

```powershell
.\upload-to-ec2.ps1 `
  -KeyPath "C:\Keys\server.pem" `
  -HostName "ec2-203-0-113-10.compute-1.amazonaws.com" `
  -UserName "ec2-user" `
  -RemoteDirectory "/home/ec2-user/DPS"
```

#### What the uploader sends

The script uploads:

- `app/`
- `public/`
- `.openai/hosting.json`
- `package.json` and `package-lock.json`
- TypeScript, Next.js, Vite, and ESLint configuration
- `deploy-ec2.sh`

It intentionally excludes generated or local-only content such as `node_modules`, `dist`, `.git`, `.next`, `.vinext`, `.wrangler`, and previous deployment archives.

The files are placed in `/home/ec2-user/DPS`, and `deploy-ec2.sh` is made executable.

### Step 2: Connect to EC2

```powershell
ssh -i "C:\path\to\your-key.pem" ec2-user@EC2_PUBLIC_IPV4
```

### Step 3: Run the deployment

On the EC2 instance:

```bash
cd /home/ec2-user/DPS
./deploy-ec2.sh dreamhighpublicschool.in
```

The domain is **required** — the script creates an nginx config in
`/etc/nginx/conf.d/dreamhigh.conf` scoped to that domain. It does **not**
overwrite the main `nginx.conf`, so it is safe to run alongside other
projects on the same server.

The deployment script:

1. Installs Git, archive utilities, and Nginx using `dnf` or `yum`. Amazon Linux's preinstalled `curl-minimal` supplies the required `curl` command.
2. Installs NVM and Node.js 22 for `ec2-user`.
3. Installs the exact project dependencies using `npm ci`.
4. Creates the production build using `npm run build`.
5. Creates and enables a `dreamhigh.service` systemd unit.
6. Configures Nginx to proxy the specified domain on port `80` to the application on `127.0.0.1:3000`.
7. Starts both services and checks the application's local HTTP response.

After a successful deployment, open:

```text
http://dreamhighpublicschool.in
```

### Step 4: Add HTTPS

After the site is live on HTTP, add a free SSL certificate with Let's Encrypt:

```bash
sudo dnf install -y certbot python3-certbot-nginx
sudo certbot --nginx -d dreamhighpublicschool.in -d www.dreamhighpublicschool.in
```

Choose option **2** (redirect HTTP to HTTPS) when prompted. Certbot automatically modifies the nginx config and sets up auto-renewal.

Enable the renewal timer:

```bash
sudo systemctl enable --now certbot-renew.timer
```

### Deployment-script configuration

The script accepts optional environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_DIR` | `/home/ec2-user/DPS` | Application directory on EC2. |
| `APP_USER` | `ec2-user` | Linux user that owns and runs the application. |

Example:

```bash
APP_DIR=/home/ec2-user/DPS APP_USER=ec2-user ./deploy-ec2.sh dreamhighpublicschool.in
```

The script is intended for Amazon Linux systems with `dnf` or `yum`.

## Updating an existing deployment

Run the uploader again from Windows:

```powershell
.\upload-to-ec2.ps1 `
  -KeyPath "C:\path\to\your-key.pem" `
  -HostName "EC2_PUBLIC_IPV4"
```

Reconnect and rerun the deployment:

```powershell
ssh -i "C:\path\to\your-key.pem" ec2-user@EC2_PUBLIC_IPV4
```

```bash
cd /home/ec2-user/DPS
./deploy-ec2.sh dreamhighpublicschool.in
```

The deployment script can be run again safely. It refreshes dependencies, rebuilds the website, updates the service configuration, and restarts the application.

## Service management

Check the application:

```bash
sudo systemctl status dreamhigh
```

Follow application logs:

```bash
sudo journalctl -u dreamhigh -f
```

Restart the application:

```bash
sudo systemctl restart dreamhigh
```

Check Nginx:

```bash
sudo nginx -t
sudo systemctl status nginx
```

Test the application without Nginx:

```bash
curl http://127.0.0.1:3000
```

Test the public web server from the instance:

```bash
curl http://127.0.0.1
```

## Troubleshooting

### SSH or SCP times out

- Confirm the instance is running and has passed its EC2 status checks.
- Confirm the command uses its public IPv4 address or public DNS name.
- Confirm the security group permits port `22` from the current public IP.

### `Permission denied (publickey)`

- Confirm the `.pem` file belongs to the key pair selected when the instance was launched.
- Confirm the Amazon Linux username is `ec2-user`.
- Restrict the key's Windows permissions if OpenSSH reports that it is unprotected.

### Website does not open

Check both services:

```bash
sudo systemctl status dreamhigh
sudo systemctl status nginx
```

Then inspect recent logs:

```bash
sudo journalctl -u dreamhigh -n 100 --no-pager
sudo journalctl -u nginx -n 100 --no-pager
```

Confirm that the EC2 security group allows inbound TCP port `80`.

During startup, the deployment script may need several seconds before the application begins accepting connections on port `3000`. The script retries automatically for up to 30 seconds and reports success only after a connection works.

### Build fails or the service keeps restarting

Check the installed versions and application logs:

```bash
source /home/ec2-user/.nvm/nvm.sh
node --version
npm --version
sudo journalctl -u dreamhigh -n 100 --no-pager
```

The Node.js version must be 22.13 or newer.

### `curl-minimal` conflicts with `curl`

Amazon Linux 2023 normally includes `curl-minimal`. It already provides the `curl` command and cannot be installed alongside the full `curl` package. The current deployment script deliberately leaves `curl-minimal` in place. If an older copy of the script reports this package conflict, upload the project again so the corrected `deploy-ec2.sh` replaces it, then rerun the deployment.

## Setting up multiple projects on the same EC2 instance

This guide covers deploying DPS alongside Skyline Empire (or any other
project) on a single EC2 server. Each app runs on its own port with its
own nginx config file in `/etc/nginx/conf.d/`.

### Prerequisites

- Amazon Linux 2023 EC2 instance (t3.micro or larger)
- Security group rules: TCP 22 (from your IP), TCP 80 + 443 (from anywhere)
- Domains pointing to the EC2 public IP:
  - GoDaddy A record `@` → EC2 IP (e.g. `dreamhighpublicschool.in`)
  - DuckDNS dashboard IP update (e.g. `skyline-empire.duckdns.org`)

### Step 1: SSH into the EC2

```bash
ssh -i "your-key.pem" ec2-user@EC2_PUBLIC_IP
```

### Step 2: Copy both projects to the server

From your local machine:

```bash
scp -r /path/to/DPS ec2-user@EC2_PUBLIC_IP:~/
scp -r /path/to/skyline-empire ec2-user@EC2_PUBLIC_IP:~/
```

### Step 3: Deploy DPS first

DPS installs nginx and nvm/Node — deploy it first so the infrastructure
is ready:

```bash
cd ~/DPS
chmod +x deploy-ec2.sh
./deploy-ec2.sh dreamhighpublicschool.in
```

Verify:

```bash
curl http://127.0.0.1:3000/
```

### Step 4: Clean up nginx default config

The default `nginx.conf` has a `default_server` block that conflicts
with multiple sites. Replace it:

```bash
sudo tee /etc/nginx/nginx.conf >/dev/null <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
}
EOF

sudo nginx -t
sudo systemctl reload nginx
```

### Step 5: Deploy Skyline Empire

```bash
cd ~/skyline-empire
chmod +x deploy/deploy.sh
sudo ./deploy/deploy.sh skyline-empire.duckdns.org
```

The script detects nvm-installed Node from DPS, copies files to
`/opt/myairline/`, creates `myairline` service (port 4173), and creates
`/etc/nginx/conf.d/skyline.conf`.

Verify:

```bash
curl http://127.0.0.1:4173/
```

### Step 6: Reload nginx and test both sites

```bash
sudo nginx -t
sudo systemctl reload nginx

curl -H "Host: dreamhighpublicschool.in" http://127.0.0.1/
curl -H "Host: skyline-empire.duckdns.org" http://127.0.0.1/
```

### Step 7: Add HTTPS for both sites

```bash
sudo dnf install -y certbot python3-certbot-nginx

# DPS
sudo certbot --nginx -d dreamhighpublicschool.in -d www.dreamhighpublicschool.in

# Skyline
sudo certbot --nginx -d skyline-empire.duckdns.org
```

Choose option **2** (redirect HTTP to HTTPS) each time.

Enable auto-renewal:

```bash
sudo systemctl enable --now certbot-renew.timer
```

### Step 8: Verify everything

From your laptop:

```bash
curl -I https://dreamhighpublicschool.in/
curl -I https://skyline-empire.duckdns.org/
```

### Final architecture

```
Internet → :80/:443 nginx
               ├── dreamhighpublicschool.in    → 127.0.0.1:3000  (dreamhigh, Next.js)
               └── skyline-empire.duckdns.org  → 127.0.0.1:4173  (myairline, Node.js)

systemd services:
  ├── dreamhigh  → npm start (port 3000)
  └── myairline  → node server.js (port 4173)

SSL: Let's Encrypt (auto-renewing via certbot-renew.timer)
```

### Updating later

Re-run the same deploy commands — they won't overwrite each other's
nginx configs or databases:

```bash
# Update DPS
cd ~/DPS && ./deploy-ec2.sh dreamhighpublicschool.in

# Update Skyline
cd ~/skyline-empire && sudo ./deploy/deploy.sh skyline-empire.duckdns.org
```

### Adding a 3rd project later

Same pattern:

1. Copy project to EC2
2. Run its deploy script with its domain (use a new port, e.g. 4175)
3. Create `/etc/nginx/conf.d/thirdapp.conf` with its domain
4. `sudo nginx -t && sudo systemctl reload nginx`
5. `sudo certbot --nginx -d third-domain.com`
