#!/usr/bin/env bash
# fix-and-deploy.sh
# Preflight checks, fixes known issues, then deploys the stack.
# Usage: bash scripts/fix-and-deploy.sh

set -euo pipefail

INSTANCE_ID="i-0eb277f732ee785ac"
REGION="us-east-1"

PASS="[PASS]"
FAIL="[FAIL]"
INFO="[INFO]"
FIX="[FIX] "

# ── Helper: run a command on EC2 via SSM and return its stdout ─────────────────
ssm_run() {
  local description="$1"
  local command="$2"
  echo "$INFO Running on EC2: $description"

  local cmd_id
  cmd_id=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$command\"]" \
    --region "$REGION" \
    --output text --query "Command.CommandId")

  sleep 5

  local output status
  output=$(aws ssm get-command-invocation \
    --command-id "$cmd_id" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "StandardOutputContent" \
    --output text 2>/dev/null || echo "")
  status=$(aws ssm get-command-invocation \
    --command-id "$cmd_id" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "StatusDetails" \
    --output text 2>/dev/null || echo "Failed")

  echo "$INFO   Status: $status"
  echo "$INFO   Output: $output"
  echo "$output"
}

echo ""
echo "============================================================"
echo "  DevOps Platform — Preflight Check + Deploy"
echo "============================================================"
echo ""

# ── CHECK 1: EC2 state ─────────────────────────────────────────────────────────
echo "--- CHECK 1: EC2 instance state ---"
STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text 2>/dev/null || echo "error")

if [[ "$STATE" == "running" ]]; then
  echo "$PASS EC2 is running"
elif [[ "$STATE" == "stopped" ]]; then
  echo "$FIX EC2 is stopped — starting it..."
  aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" > /dev/null
  echo "$INFO Waiting for instance to reach running state..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
  echo "$PASS EC2 started. Waiting 30s for services to come up..."
  sleep 30
elif [[ "$STATE" == "error" ]]; then
  echo "$FAIL Cannot reach AWS. Check your AWS credentials: aws sts get-caller-identity"
  exit 1
else
  echo "$FAIL EC2 is in state '$STATE'. Cannot continue."
  exit 1
fi

# ── CHECK 2: SSM online ────────────────────────────────────────────────────────
echo ""
echo "--- CHECK 2: SSM agent reachability ---"
for i in $(seq 1 18); do
  PING=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --region "$REGION" \
    --query "InstanceInformationList[0].PingStatus" \
    --output text 2>/dev/null || echo "None")
  if [[ "$PING" == "Online" ]]; then
    echo "$PASS SSM agent is online"
    break
  fi
  if [[ $i -eq 18 ]]; then
    echo "$FAIL SSM never came online after 3 minutes. Check IAM role + SSM agent on EC2."
    exit 1
  fi
  echo "$INFO   SSM not ready ($PING) — waiting 10s... ($i/18)"
  sleep 10
done

# ── CHECK 3: Docker daemon running ─────────────────────────────────────────────
echo ""
echo "--- CHECK 3: Docker daemon ---"
DOCKER_STATUS=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl is-active docker"]' \
  --region "$REGION" \
  --output text --query "Command.CommandId")
sleep 5
DOCKER_OUT=$(aws ssm get-command-invocation \
  --command-id "$DOCKER_STATUS" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" --output text | tr -d '\n')

if [[ "$DOCKER_OUT" == "active" ]]; then
  echo "$PASS Docker daemon is active"
else
  echo "$FIX Docker is not active ('$DOCKER_OUT') — starting it..."
  aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["systemctl start docker"]' \
    --region "$REGION" > /dev/null
  sleep 8
  echo "$PASS Docker start command sent"
fi

# ── CHECK 4: Docker Compose version ───────────────────────────────────────────
echo ""
echo "--- CHECK 4: Docker Compose plugin ---"
COMPOSE_CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker compose version 2>&1"]' \
  --region "$REGION" \
  --output text --query "Command.CommandId")
sleep 5
COMPOSE_OUT=$(aws ssm get-command-invocation \
  --command-id "$COMPOSE_CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" --output text | tr -d '\n')
if [[ "$COMPOSE_OUT" == *"version"* ]]; then
  echo "$PASS $COMPOSE_OUT"
else
  echo "$FAIL Docker Compose not found. Run: make provision"
  exit 1
fi

# ── CHECK 5: Docker buildx version ────────────────────────────────────────────
echo ""
echo "--- CHECK 5: Docker buildx plugin ---"
BUILDX_CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker buildx version 2>&1"]' \
  --region "$REGION" \
  --output text --query "Command.CommandId")
sleep 5
BUILDX_OUT=$(aws ssm get-command-invocation \
  --command-id "$BUILDX_CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" --output text | tr -d '\n')

if [[ "$BUILDX_OUT" == *"v0."* ]]; then
  BUILDX_VER=$(echo "$BUILDX_OUT" | grep -oP 'v[0-9]+\.[0-9]+' | head -1)
  BUILDX_MINOR=$(echo "$BUILDX_VER" | grep -oP '[0-9]+$')
  if [[ "$BUILDX_MINOR" -ge 17 ]]; then
    echo "$PASS buildx $BUILDX_VER (>= 0.17.0 required)"
  else
    echo "$FIX buildx $BUILDX_VER is too old — installing latest..."
    INSTALL_ID=$(aws ssm send-command \
      --cli-input-json file://scripts/install-buildx.json \
      --region "$REGION" \
      --output text --query "Command.CommandId")
    sleep 20
    INSTALL_OUT=$(aws ssm get-command-invocation \
      --command-id "$INSTALL_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardOutputContent" --output text)
    echo "$PASS $INSTALL_OUT"
  fi
else
  echo "$FIX buildx not found — installing..."
  INSTALL_ID=$(aws ssm send-command \
    --cli-input-json file://scripts/install-buildx.json \
    --region "$REGION" \
    --output text --query "Command.CommandId")
  sleep 20
  INSTALL_OUT=$(aws ssm get-command-invocation \
    --command-id "$INSTALL_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "StandardOutputContent" --output text)
  echo "$PASS $INSTALL_OUT"
fi

# ── CHECK 6: DNS resolution inside Docker containers ─────────────────────────
echo ""
echo "--- CHECK 6: Docker container DNS ---"
DNS_CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker run --rm alpine nslookup deb.debian.org > /dev/null 2>&1 && echo DNS_OK || echo DNS_FAIL"]' \
  --region "$REGION" \
  --output text --query "Command.CommandId")
sleep 10
DNS_OUT=$(aws ssm get-command-invocation \
  --command-id "$DNS_CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" --output text | tr -d '\n')

if [[ "$DNS_OUT" == *"DNS_OK"* ]]; then
  echo "$PASS Docker container DNS is working"
else
  echo "$FIX Docker container DNS is broken — applying fix..."
  FIX_ID=$(aws ssm send-command \
    --cli-input-json file://scripts/fix-docker-dns.json \
    --region "$REGION" \
    --output text --query "Command.CommandId")
  sleep 15
  FIX_OUT=$(aws ssm get-command-invocation \
    --command-id "$FIX_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "[StatusDetails, StandardOutputContent]" \
    --output text)
  echo "$INFO   $FIX_OUT"
  if [[ "$FIX_OUT" == *"DNS_OK"* ]]; then
    echo "$PASS Docker DNS fixed"
  else
    echo "$FAIL Docker DNS fix failed. Output: $FIX_OUT"
    exit 1
  fi
fi

# ── CHECK 7: /opt/platform exists and has key files ───────────────────────────
echo ""
echo "--- CHECK 6: Platform directory on EC2 ---"
FILES_CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["ls /opt/platform/ 2>/dev/null || echo MISSING"]' \
  --region "$REGION" \
  --output text --query "Command.CommandId")
sleep 5
FILES_OUT=$(aws ssm get-command-invocation \
  --command-id "$FILES_CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" --output text)
if [[ "$FILES_OUT" == *"docker-compose.yml"* ]]; then
  echo "$PASS /opt/platform exists with docker-compose.yml"
else
  echo "$INFO /opt/platform not ready yet — will be created by deploy"
fi

# ── CHECK 7: .env file exists locally ─────────────────────────────────────────
echo ""
echo "--- CHECK 7: Local .env file ---"
if [[ -f "platform/.env" ]]; then
  # Check required keys are present and not empty
  MISSING=()
  for key in GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD JENKINS_ADMIN_PASSWORD GHCR_USERNAME GHCR_TOKEN; do
    if ! grep -q "^${key}=.\+" platform/.env; then
      MISSING+=("$key")
    fi
  done
  if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "$PASS platform/.env exists with all required keys"
  else
    echo "$FAIL platform/.env is missing values for: ${MISSING[*]}"
    exit 1
  fi
else
  echo "$FAIL platform/.env not found. Copy platform/.env.example to platform/.env and fill in values."
  exit 1
fi

# ── ALL CHECKS PASSED ─────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  All checks passed. Starting deployment..."
echo "============================================================"
echo ""

make deploy
