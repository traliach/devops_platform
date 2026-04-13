#!/usr/bin/env bash
# scripts/backup.sh
# Backup Jenkins home, Prometheus data, and Grafana data from EC2 to S3.
# Triggered manually or via Ansible backup.yml playbook.
#
# Usage: bash scripts/backup.sh
#
# Required env vars (or defaults used):
#   BACKUP_BUCKET  — S3 bucket for backups (default: achille-tf-state)
#   BACKUP_PREFIX  — S3 key prefix (default: devops-platform-lab/backups)
#   AWS_REGION     — AWS region (default: us-east-1)

set -euo pipefail

INSTANCE_ID="i-0eb277f732ee785ac"
BACKUP_BUCKET="${BACKUP_BUCKET:-achille-tf-state}"
BACKUP_PREFIX="${BACKUP_PREFIX:-devops-platform-lab/backups}"
REGION="${AWS_REGION:-us-east-1}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
section() { echo ""; echo -e "${CYAN}━━━ $* ━━━${NC}"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "aws CLI not found"

echo ""
echo "=============================================="
echo "  devops-platform-lab — Backup               "
echo "  Timestamp: $TIMESTAMP                       "
echo "=============================================="

section "Triggering backup on EC2 via SSM"
info "Target: s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/${TIMESTAMP}/"

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"set -euo pipefail\",
    \"TIMESTAMP=${TIMESTAMP}\",
    \"BACKUP_DEST=s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/${TIMESTAMP}\",
    \"echo Backing up Jenkins home...\",
    \"docker run --rm -v jenkins_home:/data -v /tmp:/backup alpine tar czf /backup/jenkins_home.tar.gz -C /data .\",
    \"aws s3 cp /tmp/jenkins_home.tar.gz \\\$BACKUP_DEST/jenkins_home.tar.gz\",
    \"rm -f /tmp/jenkins_home.tar.gz\",
    \"echo Backing up Prometheus data...\",
    \"docker run --rm -v prometheus_data:/data -v /tmp:/backup alpine tar czf /backup/prometheus_data.tar.gz -C /data .\",
    \"aws s3 cp /tmp/prometheus_data.tar.gz \\\$BACKUP_DEST/prometheus_data.tar.gz\",
    \"rm -f /tmp/prometheus_data.tar.gz\",
    \"echo Backing up Grafana data...\",
    \"docker run --rm -v grafana_data:/data -v /tmp:/backup alpine tar czf /backup/grafana_data.tar.gz -C /data .\",
    \"aws s3 cp /tmp/grafana_data.tar.gz \\\$BACKUP_DEST/grafana_data.tar.gz\",
    \"rm -f /tmp/grafana_data.tar.gz\",
    \"echo Done. Listing backup:\",
    \"aws s3 ls \\\$BACKUP_DEST/\"
  ]" \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

info "Command ID: $CMD_ID — waiting for backup to complete..."

for i in $(seq 1 36); do
  sleep 10
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Status" --output text 2>/dev/null || echo "Pending")

  if [[ "$STATUS" == "Success" ]]; then
    OUTPUT=$(aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardOutputContent" \
      --output text)
    echo "$OUTPUT"
    pass "Backup complete — s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/${TIMESTAMP}/"
    break
  elif [[ "$STATUS" == "Failed" ]]; then
    OUTPUT=$(aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardErrorContent" \
      --output text)
    echo "$OUTPUT"
    fail "Backup failed"
    exit 1
  fi

  echo "    still waiting... ($((i*10))s)"
done
