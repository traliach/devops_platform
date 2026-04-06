#!/usr/bin/env bash
# check-jenkins.sh — run all Jenkins health checks in one shot via SSM
# Usage: bash scripts/check-jenkins.sh

INSTANCE_ID="i-0eb277f732ee785ac"
REGION="us-east-1"

echo "==> Sending checks to EC2..."
CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=[
    "echo === CONTAINER STATUS ===",
    "docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Image}}\" | grep -E \"(NAMES|jenkins|prometheus|grafana)\"",
    "echo === DOCKER BINARY ===",
    "docker exec jenkins which docker 2>&1 || echo NOT_FOUND",
    "echo === DOCKER VERSION IN CONTAINER ===",
    "docker exec jenkins docker --version 2>&1",
    "echo === SOCKET PERMISSION (jenkins user) ===",
    "docker exec -u jenkins jenkins docker ps 2>&1 | head -2",
    "echo === SOCKET GID ===",
    "stat -c \"%g\" /var/run/docker.sock",
    "echo === JENKINS GROUP MEMBERSHIPS ===",
    "docker exec jenkins id jenkins 2>&1",
    "echo === CASC ERRORS (last 20 lines) ===",
    "docker logs jenkins 2>&1 | grep -iE \"(casc|jcasc|severe|error|exception)\" | grep -v DiskUsage | tail -20"
  ]' \
  --region "$REGION" \
  --output text --query "Command.CommandId")

echo "==> Command ID: $CMD_ID"
echo "==> Waiting for results..."

for i in $(seq 1 20); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Status" --output text 2>/dev/null)

  if [[ "$STATUS" == "Success" || "$STATUS" == "Failed" ]]; then
    echo "==> Status: $STATUS"
    aws ssm get-command-invocation \
      --command-id "$CMD_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardOutputContent" \
      --output text
    break
  fi

  echo "    still waiting... ($((i*5))s)"
done