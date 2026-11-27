#!/bin/bash
# Rebuilds the public dashboard from the verified reports in S3 and serves it on port 80.
# run-scan.sh calls this at the end of every run. Usage: dashboard.sh [commit sha]
# When a sha is given, it waits up to 60s for the Lambda to write verified/<sha>.json.

set -u

APP_DIR="/opt/app"
BUCKET="team13-vsp-reports-33c3b3e1"
REGION="us-east-1"
OUT_DIR="/opt/dashboard"
DATA_DIR="$OUT_DIR/data"
CONTAINER="team13-dashboard"
SCAN_ID="${1:-}"

mkdir -p "$DATA_DIR"

if [ -n "$SCAN_ID" ]; then
  for _ in $(seq 1 12); do
    if aws s3api head-object --bucket "$BUCKET" --key "verified/${SCAN_ID}.json" --region "$REGION" >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
fi

aws s3 sync "s3://${BUCKET}/verified/" "$DATA_DIR" --region "$REGION" --delete --only-show-errors \
  || echo "dashboard: could not sync verified reports, showing the last copy"

python3 "$APP_DIR/scripts/render-dashboard.py" "$DATA_DIR" "$OUT_DIR/index.html" \
  || { echo "dashboard: could not build the page"; exit 1; }

# Start the web server once. It serves the folder read-only, so new pages show up without a restart.
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  docker run -d --name "$CONTAINER" --restart unless-stopped \
    -p 80:80 --memory 64m \
    -v "$OUT_DIR:/usr/share/nginx/html:ro" \
    nginx:1.27-alpine >/dev/null || { echo "dashboard: could not start the web server"; exit 1; }
fi

echo "dashboard: updated"
