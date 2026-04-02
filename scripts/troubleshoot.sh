#!/usr/bin/env bash
# scripts/troubleshoot.sh
# Run from WSL to validate the full stack before running Ansible.
# Checks: AWS credentials, EC2 state, SSM connectivity, Ansible, collections.
#
# Usage: bash scripts/troubleshoot.sh

set -euo pipefail

INSTANCE_ID="i-0eb277f732ee785ac"
AWS_REGION="us-east-1"
ANSIBLE_DIR="$HOME/devops-platform-lab/ansible"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
section() { echo ""; echo -e "${CYAN}━━━ $* ━━━${NC}"; }

echo ""
echo "=============================================="
echo "  devops-platform-lab — Troubleshoot Script  "
echo "=============================================="

# ── 1. AWS credentials ────────────────────────────────────────────────────────
section "1. AWS Credentials"
if ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  pass "AWS credentials valid — account: $ACCOUNT"
  IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null)
  info "User ARN: $(echo "$IDENTITY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Arn"])')"
else
  fail "AWS credentials not configured or expired"
  echo "  Fix: aws configure"
  exit 1
fi

# ── 2. EC2 instance state ─────────────────────────────────────────────────────
section "2. EC2 Instance State"
STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$STATE" == "running" ]]; then
  pass "Instance $INSTANCE_ID is running"
  PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
  info "Public IP: $PUBLIC_IP"
elif [[ "$STATE" == "stopped" ]]; then
  fail "Instance is STOPPED — start it first:"
  echo "  aws ec2 start-instances --instance-ids $INSTANCE_ID --region $AWS_REGION"
  exit 1
else
  fail "Instance state: $STATE"
  exit 1
fi

# ── 3. SSM agent reachability ─────────────────────────────────────────────────
section "3. SSM Agent Reachability"
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query "InstanceInformationList[0].PingStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$SSM_STATUS" == "Online" ]]; then
  pass "SSM agent is Online"
  SSM_VERSION=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "InstanceInformationList[0].AgentVersion" \
    --output text)
  info "SSM agent version: $SSM_VERSION"
else
  fail "SSM agent status: $SSM_STATUS"
  echo "  The instance may still be initializing. Wait 2 minutes and retry."
  echo "  Or check: IAM role has AmazonSSMManagedInstanceCore policy attached"
fi

# ── 4. Session Manager plugin ─────────────────────────────────────────────────
section "4. Session Manager Plugin (local)"
if command -v session-manager-plugin >/dev/null 2>&1; then
  pass "session-manager-plugin installed"
  session-manager-plugin --version 2>/dev/null || true
else
  fail "session-manager-plugin not installed"
  echo "  Fix:"
  echo "    curl 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb' -o /tmp/ssm-plugin.deb"
  echo "    sudo dpkg -i /tmp/ssm-plugin.deb"
fi

# ── 5. Ansible installation ───────────────────────────────────────────────────
section "5. Ansible"
if command -v ansible >/dev/null 2>&1; then
  pass "ansible installed: $(ansible --version | head -1)"
else
  fail "ansible not found"
  echo "  Fix: sudo apt install ansible-core"
fi

if command -v ansible-playbook >/dev/null 2>&1; then
  pass "ansible-playbook available"
else
  fail "ansible-playbook not found"
fi

# ── 6. Ansible collections ────────────────────────────────────────────────────
section "6. Ansible Collections"
for collection in community.aws amazon.aws; do
  if ansible-galaxy collection list 2>/dev/null | grep -q "$collection"; then
    pass "Collection installed: $collection"
  else
    fail "Collection missing: $collection"
    echo "  Fix: ansible-galaxy collection install -r $ANSIBLE_DIR/requirements.yml"
  fi
done

# ── 7. Ansible inventory ping ─────────────────────────────────────────────────
section "7. Ansible Inventory Ping"
info "Running ansible ping against $INSTANCE_ID ..."
if ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" \
   ANSIBLE_ROLES_PATH="$ANSIBLE_DIR/roles" \
   ansible -i "$ANSIBLE_DIR/inventory/hosts.ini" platform -m ping 2>&1; then
  pass "Ansible can reach the instance"
else
  fail "Ansible cannot reach the instance"
  echo "  Check: SSM plugin installed, AWS credentials valid, instance running"
fi

# ── 8. Syntax check ───────────────────────────────────────────────────────────
section "8. Docker Package Availability on EC2"
info "Checking if 'docker' package is available in AL2023 repos on the instance..."
DOCKER_CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["dnf info docker 2>&1 | head -5"]' \
  --region "$AWS_REGION" \
  --query "Command.CommandId" \
  --output text 2>/dev/null || echo "FAILED")

if [[ "$DOCKER_CMD_ID" != "FAILED" ]]; then
  sleep 4
  DOCKER_OUT=$(aws ssm get-command-invocation \
    --command-id "$DOCKER_CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "StandardOutputContent" \
    --output text 2>/dev/null || echo "")
  if echo "$DOCKER_OUT" | grep -qi "name.*docker\|available packages"; then
    pass "Docker package available in Amazon repos"
    echo "$DOCKER_OUT" | head -3 | sed 's/^/  /'
  else
    fail "Docker package NOT found — repo issue"
    echo "  Raw output: $DOCKER_OUT"
  fi
else
  warn "Could not run SSM command to check Docker"
fi

section "9. Playbook Syntax Check"
if ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" \
   ANSIBLE_ROLES_PATH="$ANSIBLE_DIR/roles" \
   ansible-playbook "$ANSIBLE_DIR/playbooks/provision.yml" \
     --syntax-check \
     -i "$ANSIBLE_DIR/inventory/hosts.ini" \
     -e "@$ANSIBLE_DIR/group_vars/all/vars.yml" 2>&1; then
  pass "Playbook syntax is valid"
else
  fail "Playbook has syntax errors — fix before running"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
info "If all checks pass, run:"
echo "  cd ~/devops-platform-lab && make provision"
echo "=============================================="
echo ""
