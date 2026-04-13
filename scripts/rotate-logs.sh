#!/usr/bin/env bash
# scripts/rotate-logs.sh
# Rotate Docker container logs on EC2 to prevent disk exhaustion.
# Truncates log files for all platform containers.
#
# Usage: bash scripts/rotate-logs.sh
#
# Note: Docker log rotation is also configured per-service in docker-compose.yml
# (max-size, max-file). This script is a manual safety valve.

set -euo pipefail

INSTANCE_ID="i-0eb277f732ee785ac"
REGION="${AWS_REGION:-us-east-1}"

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
echo "  devops-platform-lab — Log Rotation          "
echo "=============================================="

section "Rotating logs on EC2 via SSM"

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo === DISK USAGE BEFORE ===",
    "df -h /",
    "echo === LOG SIZES BEFORE ===",
    "find /var/lib/docker/containers -name \"*-json.log\" -exec du -sh {} \\; 2>/dev/null | sort -rh | head -10",
    "echo === TRUNCATING LOGS ===",
    "for ctr in jenkins prometheus grafana manga-hub; do",
    "  LOG=$(docker inspect --format=\"{{.LogPath}}\" $ctr 2>/dev/null) && [ -f \"$LOG\" ] && truncate -s 0 \"$LOG\" && echo \"Rotated: $ctr\" || echo \"Skipped: $ctr (not running)\";",
    "done",
    "echo === DISK USAGE AFTER ===",
    "df -h /"
  ]' \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

info "Command ID: $CMD_ID — waiting..."

for i in $(seq 1 12); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Status" --output text 2>/dev/null || echo "Pending")

  if [[ "$STATUS" == "Success" || "$STATUS" == "Failed" ]]; then
    aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardOutputContent" \
      --output text

    [[ "$STATUS" == "Success" ]] && pass "Log rotation complete" || fail "Log rotation failed"
    break
  fi

  echo "    still waiting... ($((i*5))s)"
done
