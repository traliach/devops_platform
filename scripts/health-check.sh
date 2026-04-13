#!/usr/bin/env bash
# scripts/health-check.sh
# Check all platform services are running on EC2 via SSM.
# Validates: Docker daemon, Jenkins, Prometheus, Grafana, manga-hub.
#
# Usage: bash scripts/health-check.sh

set -euo pipefail

INSTANCE_ID="i-0eb277f732ee785ac"
REGION="us-east-1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
section() { echo ""; echo -e "${CYAN}━━━ $* ━━━${NC}"; }

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
command -v aws >/dev/null 2>&1 || die "aws CLI not found"

echo ""
echo "=============================================="
echo "  devops-platform-lab — Health Check          "
echo "=============================================="

# ── 1. EC2 state ──────────────────────────────────────────────────────────────
section "1. EC2 Instance"
STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text 2>/dev/null || echo "unknown")

if [[ "$STATE" == "running" ]]; then
  pass "EC2 instance is running"
  PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
  info "Public IP: $PUBLIC_IP"
else
  fail "EC2 instance state: $STATE"
  exit 1
fi

# ── 2. Docker + services via SSM ──────────────────────────────────────────────
section "2. Docker Services (via SSM)"
info "Sending health check commands to EC2..."

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo === DOCKER DAEMON ===",
    "systemctl is-active docker",
    "echo === CONTAINER STATUS ===",
    "docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"",
    "echo === SERVICE HEALTH ===",
    "for svc in jenkins prometheus grafana; do docker inspect --format \"{{.Name}} {{.State.Health.Status}}\" $svc 2>/dev/null || echo \"$svc not found\"; done",
    "echo === PROMETHEUS TARGETS ===",
    "docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | python3 -c \"import sys,json; targets=json.load(sys.stdin)['"'"'data'"'"']['"'"'activeTargets'"'"']; [print(t['"'"'labels'"'"']['"'"'job'"'"'], t['"'"'health'"'"']) for t in targets]\" 2>/dev/null || echo skipped",
    "echo === ALERT RULES ===",
    "docker exec prometheus promtool check rules /etc/prometheus/alerts/rules.yml 2>&1"
  ]' \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

info "Command ID: $CMD_ID — waiting for results..."

for i in $(seq 1 24); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Status" --output text 2>/dev/null || echo "Pending")

  if [[ "$STATUS" == "Success" || "$STATUS" == "Failed" ]]; then
    OUTPUT=$(aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardOutputContent" \
      --output text)
    echo "$OUTPUT"

    if [[ "$STATUS" == "Success" ]]; then
      echo ""
      pass "Health check complete"
    else
      fail "One or more checks returned non-zero"
    fi
    break
  fi

  echo "    still waiting... ($((i*5))s)"
done
