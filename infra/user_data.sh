#!/bin/bash
set -eux
dnf install -y docker git cronie
systemctl enable --now docker
systemctl enable --now crond
usermod -aG docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
rm -rf /opt/app
git clone https://github.com/neera-jk/verified-security-pipeline.git /opt/app
git config --system --add safe.directory /opt/app
chmod +x /opt/app/scripts/run-scan.sh

cat > /etc/cron.d/team13-scan <<'CRON'
0 * * * * root flock -n /tmp/team13-scan.lock /opt/app/scripts/run-scan.sh >> /var/log/team13-scan.log 2>&1
CRON
chmod 644 /etc/cron.d/team13-scan

/opt/app/scripts/run-scan.sh >> /var/log/team13-scan.log 2>&1 || true

echo "ready $(date)" > /var/log/team13-ready
