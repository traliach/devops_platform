#!/usr/bin/env bash
# scripts/setup-prerequisites.sh
# Run once before Sprint 1 (Terraform).
#
# What this does:
#   1. Generates a local SSH key pair (devops-platform-lab-key)
#   2. Detects your current public IP for the security group
#   3. Prompts for a GHCR token (needed by release.yml to push Docker images)
#   4. Sets all required GitHub Actions secrets
#
# Terraform will upload the SSH public key to AWS — never create the key pair manually.
# Your private key never leaves your machine.
#
# Usage: bash scripts/setup-prerequisites.sh

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────────
AWS_REGION="us-east-1"
KEY_NAME="devops-platform-lab-key"
KEY_PATH="$HOME/.ssh/${KEY_NAME}"
GITHUB_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo '')"
# ───────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "================================================"
echo "  devops-platform-lab — Prerequisites Setup     "
echo "================================================"
echo ""

# ─── Preflight checks ──────────────────────────────────────────────────────────
command -v aws        >/dev/null 2>&1 || error "aws CLI not found.   Install: https://aws.amazon.com/cli/"
command -v gh         >/dev/null 2>&1 || error "gh CLI not found.    Install: https://cli.github.com/"
command -v ssh-keygen >/dev/null 2>&1 || error "ssh-keygen not found."
command -v curl       >/dev/null 2>&1 || error "curl not found."

info "Verifying AWS credentials..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || error "AWS credentials not configured. Run: aws configure"
success "AWS account: $AWS_ACCOUNT_ID"

info "Verifying GitHub auth..."
gh auth status >/dev/null 2>&1 || error "Not logged in to GitHub. Run: gh auth login"
success "GitHub: $(gh api user -q .login)"

if [[ -z "$GITHUB_REPO" ]]; then
  echo ""
  read -rp "Enter your GitHub repo (owner/repo, e.g. traliach/devops_platform): " GITHUB_REPO
fi
echo ""

# ─── Step 1: SSH key pair ──────────────────────────────────────────────────────
info "Step 1/4 — Generating SSH key pair"

if [[ -f "$KEY_PATH" ]]; then
  warn "Key already exists at $KEY_PATH — skipping generation."
else
  mkdir -p "$(dirname "$KEY_PATH")"
  ssh-keygen -t ed25519 -C "$KEY_NAME" -f "$KEY_PATH" -N ""
  chmod 600 "$KEY_PATH"
  chmod 644 "${KEY_PATH}.pub"
  success "Private key : $KEY_PATH"
  success "Public key  : ${KEY_PATH}.pub"
fi

PUBLIC_KEY_CONTENT=$(cat "${KEY_PATH}.pub")
echo ""
info "Public key Terraform will upload to AWS:"
echo "  $PUBLIC_KEY_CONTENT"
echo ""

# ─── Step 2: Detect public IP ─────────────────────────────────────────────────
info "Step 2/4 — Detecting your public IP"

MY_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com || true)
[[ -z "$MY_IP" ]] && error "Could not detect public IP. Check your internet connection."
success "Your public IP: $MY_IP"

SSH_CIDR="${MY_IP}/32"
warn "This IP will be added to the security group for SSH / Jenkins / Grafana access."
warn "Working from multiple locations? Add more CIDRs to allowed_ssh_cidrs in terraform.tfvars later."
echo ""

# ─── Step 3: GHCR token ───────────────────────────────────────────────────────
info "Step 3/4 — GitHub Container Registry (GHCR) token"
echo ""
echo "  Required by release.yml to push the Flask app Docker image to GHCR."
echo "  Create a PAT at: https://github.com/settings/tokens"
echo "  Scopes needed:   write:packages, read:packages, delete:packages"
echo ""
read -rsp "  Paste your GHCR token: " GHCR_TOKEN
echo ""
[[ -z "$GHCR_TOKEN" ]] && error "GHCR token cannot be empty."
echo ""

# ─── Step 4: Set GitHub Actions secrets ───────────────────────────────────────
info "Step 4/4 — Setting GitHub Actions secrets on '$GITHUB_REPO'"
echo ""

AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null \
  || error "Could not read AWS_ACCESS_KEY_ID from aws configure. Run: aws configure")
AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null \
  || error "Could not read AWS_SECRET_ACCESS_KEY from aws configure. Run: aws configure")

set_secret() {
  local name="$1"
  local value="$2"
  printf "  Setting %-38s ... " "$name"
  echo "$value" | gh secret set "$name" --repo "$GITHUB_REPO"
  echo -e "${GREEN}done${NC}"
}

set_secret "AWS_ACCESS_KEY_ID"          "$AWS_ACCESS_KEY_ID"
set_secret "AWS_SECRET_ACCESS_KEY"      "$AWS_SECRET_ACCESS_KEY"
set_secret "GHCR_TOKEN"                 "$GHCR_TOKEN"
set_secret "TF_VAR_aws_region"          "$AWS_REGION"
set_secret "TF_VAR_public_key"          "$PUBLIC_KEY_CONTENT"
# Terraform list variable — format: ["x.x.x.x/32"]
set_secret "TF_VAR_allowed_ssh_cidrs"   "[\"${SSH_CIDR}\"]"

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
success "Prerequisites complete!"
echo ""
echo "  SSH private key : $KEY_PATH"
echo "  SSH public key  : ${KEY_PATH}.pub"
echo "  Allowed SSH IP  : $SSH_CIDR"
echo ""
echo "  GitHub secrets set:"
echo "    - AWS_ACCESS_KEY_ID"
echo "    - AWS_SECRET_ACCESS_KEY"
echo "    - GHCR_TOKEN"
echo "    - TF_VAR_aws_region"
echo "    - TF_VAR_public_key"
echo "    - TF_VAR_allowed_ssh_cidrs"
echo ""
warn "Terraform will create the AWS key pair from the public key above."
warn "Your private key never leaves your machine."
echo ""
echo "  Next step:"
echo "    cd infra"
echo "    terraform init"
echo "    terraform plan"
echo "================================================"
echo ""
