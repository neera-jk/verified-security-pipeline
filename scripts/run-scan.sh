#!/bin/bash
# Runs one scan of the latest commit on main and uploads both reports to S3.
# Cron runs this hourly. The missed-run alarm watches the metric sent at the end.

set -u

APP_DIR="/opt/app"
BUCKET="team13-vsp-reports-33c3b3e1"
REGION="us-east-1"
METRIC_NAMESPACE="Team13"
METRIC_NAME="ScanSucceeded"

# Published by the docker-publish workflow, tagged with the commit SHA
IMAGE_REPO="neerajkum/team13-test-target"

# Image name docker-compose.yml uses for the test target and pentest
LOCAL_IMAGE="team13-pentest:local"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

fail() {
  log "FAILED: $1"
  exit 1
}

skip() {
  log "SKIPPED: $1"
  exit 0
}

log "Starting scan"

cd "$APP_DIR" || fail "could not open $APP_DIR"
git pull --ff-only || fail "git pull failed"

SCAN_ID=$(git rev-parse HEAD)
log "Scanning commit $SCAN_ID"

# If the image isn't published yet, the next hourly run picks it up
PUBLISHED_IMAGE="${IMAGE_REPO}:${SCAN_ID}"
if ! docker pull "$PUBLISHED_IMAGE"; then
  skip "image $PUBLISHED_IMAGE is not on Docker Hub yet"
fi

# Logged so it can be matched against Docker Hub
IMAGE_DIGEST=$(docker image inspect --format '{{index .RepoDigests 0}}' "$PUBLISHED_IMAGE")
log "Using published image $IMAGE_DIGEST"

# Compose uses an existing image with this name instead of building one
docker tag "$PUBLISHED_IMAGE" "$LOCAL_IMAGE" || fail "could not tag the published image"

# Clear old reports so a failed scan can't upload last run's files
mkdir -p reports
rm -f reports/sast.json reports/pentest.json
chmod 777 reports

# SAST has no published image, so it is built locally
docker compose build sast || fail "SAST image build failed"

# No --build, it would overwrite the pulled image
docker compose up -d --force-recreate --wait test-target || fail "test target did not start"
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