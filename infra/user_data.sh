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

SCAN_ID=$(git rev-parse HEAD)
BUCKET=team13-vsp-reports-33c3b3e1
for i in $(seq 1 60); do
  if [ -s reports/sast.json ] && [ -s reports/pentest.json ]; then break; fi
  sleep 5
done
aws s3 cp reports/sast.json "s3://${BUCKET}/sast/${SCAN_ID}.json"
aws s3 cp reports/pentest.json "s3://${BUCKET}/pentest/${SCAN_ID}.json"
echo "uploaded ${SCAN_ID}" > /var/log/team13-upload

echo "ready $(date)" > /var/log/team13-ready
