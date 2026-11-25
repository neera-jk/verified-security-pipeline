#!/bin/bash
# Runs one scan: pulls main, runs SAST and pentest, uploads reports to S3.
# The CloudWatch metric at the end is what the missed-run alarm watches.

set -u

APP_DIR="/opt/app"
BUCKET="team13-vsp-reports-33c3b3e1"
REGION="us-east-1"
METRIC_NAMESPACE="Team13"
METRIC_NAME="ScanSucceeded"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

fail() {
  log "FAILED: $1"
  exit 1
}

log "Starting scan"

cd "$APP_DIR" || fail "could not open $APP_DIR"
git pull --ff-only || fail "git pull failed"

SCAN_ID=$(git rev-parse HEAD)
log "Scanning commit $SCAN_ID"

# Clear old reports so a failed scan can't upload last run's files
mkdir -p reports
rm -f reports/sast.json reports/pentest.json
chmod 777 reports

docker compose up -d --build --wait test-target || fail "test target did not start"
docker compose run --rm sast || fail "SAST failed"
docker compose run --rm pentest || fail "pentest failed"

if [ ! -s reports/sast.json ]; then
  fail "sast.json is missing or empty"
fi

if [ ! -s reports/pentest.json ]; then
  fail "pentest.json is missing or empty"
fi

aws s3 cp reports/sast.json "s3://${BUCKET}/sast/${SCAN_ID}.json" --region "$REGION" || fail "SAST upload failed"
aws s3 cp reports/pentest.json "s3://${BUCKET}/pentest/${SCAN_ID}.json" --region "$REGION" || fail "pentest upload failed"

aws cloudwatch put-metric-data \
  --namespace "$METRIC_NAMESPACE" \
  --metric-name "$METRIC_NAME" \
  --value 1 \
  --region "$REGION" || fail "could not send metric"

log "Finished scan for $SCAN_ID"