#!/bin/bash
set -eux
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
rm -rf /opt/app
git clone https://github.com/neera-jk/verified-security-pipeline.git /opt/app
cd /opt/app
mkdir -p reports
chmod 777 reports
docker compose up -d --build
echo "ready $(date)" > /var/log/team13-ready
