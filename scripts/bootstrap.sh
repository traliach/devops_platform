#!/usr/bin/env bash
# scripts/bootstrap.sh
# First-time local setup for the devops-platform-lab control node (WSL).
# Run once after cloning the repo to validate prerequisites and install dependencies.
#
# Usage: bash scripts/bootstrap.sh
#
# What it checks / installs:
#   - AWS CLI configured and pointing to us-east-1
#   - Ansible + ansible-lint installed
#   - Ansible Galaxy collections (community.aws, amazon.aws)
#   - Session Manager plugin for WSL
#   - Symlink ~/devops-platform-lab → repo root (avoids path-with-spaces issues)
#   - ~/.vault_pass file prompt

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYMLINK="$HOME/devops-platform-lab"
REGION="us-east-1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
section() { echo ""; echo -e "${CYAN}━━━ $* ━━━${NC}"; }

echo ""
echo "=============================================="
echo "  devops-platform-lab — Bootstrap             "
echo "=============================================="

# ── 1. AWS CLI ────────────────────────────────────────────────────────────────
section "1. AWS CLI"
if command -v aws >/dev/null 2>&1; then
  pass "aws CLI found: $(aws --version 2>&1 | head -1)"
  if aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    pass "AWS credentials valid — account: $ACCOUNT"
  else
    fail "AWS credentials not configured. Run: aws configure"
    exit 1
  fi
else
  fail "aws CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
  exit 1
fi

# ── 2. Ansible ────────────────────────────────────────────────────────────────
section "2. Ansible"
if command -v ansible >/dev/null 2>&1; then
  pass "ansible found: $(ansible --version | head -1)"
else
  info "Installing ansible-core and ansible-lint..."
  sudo apt-get update -qq && sudo apt-get install -y ansible ansible-lint
  pass "ansible installed"
fi

if command -v ansible-lint >/dev/null 2>&1; then
  pass "ansible-lint found"
else
  info "Installing ansible-lint..."
  pip install ansible-lint
fi

# ── 3. Ansible Galaxy collections ────────────────────────────────────────────
section "3. Ansible Galaxy Collections"
REQUIREMENTS="$REPO_DIR/ansible/requirements.yml"
if [[ -f "$REQUIREMENTS" ]]; then
  ansible-galaxy collection install -r "$REQUIREMENTS" --upgrade
  pass "Galaxy collections installed"
else
  warn "No requirements.yml found at $REQUIREMENTS"
fi

# ── 4. Session Manager plugin ─────────────────────────────────────────────────
section "4. Session Manager Plugin"
if command -v session-manager-plugin >/dev/null 2>&1; then
  pass "session-manager-plugin already installed"
else
  info "Installing Session Manager plugin..."
  curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
    -o /tmp/session-manager-plugin.deb
  sudo dpkg -i /tmp/session-manager-plugin.deb
  rm -f /tmp/session-manager-plugin.deb
  pass "session-manager-plugin installed"
fi

# ── 5. WSL symlink ────────────────────────────────────────────────────────────
section "5. WSL Symlink"
if [[ -L "$SYMLINK" ]]; then
  pass "Symlink already exists: $SYMLINK → $(readlink "$SYMLINK")"
elif [[ -d "$SYMLINK" ]]; then
  warn "$SYMLINK exists as a real directory — skipping symlink creation"
else
  ln -s "$REPO_DIR" "$SYMLINK"
  pass "Created symlink: $SYMLINK → $REPO_DIR"
fi

# ── 6. Vault password file ────────────────────────────────────────────────────
section "6. Ansible Vault Password File"
if [[ -f "$HOME/.vault_pass" ]]; then
  pass "~/.vault_pass already exists"
else
  warn "~/.vault_pass not found"
  read -rsp "Enter vault password (will be saved to ~/.vault_pass): " VAULT_PASS
  echo ""
  echo "$VAULT_PASS" > "$HOME/.vault_pass"
  chmod 600 "$HOME/.vault_pass"
  pass "~/.vault_pass created (chmod 600)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
pass "Bootstrap complete. Next steps:"
echo "  cd ~/devops-platform-lab"
echo "  make provision-check   # dry-run Ansible"
echo "  make provision         # run Ansible"
echo "  make deploy            # sync files + start stack"
echo "=============================================="
echo ""
