# Makefile — devops-platform-lab
#
# Wraps all deploy and operations commands so they can be run with `make <target>`
# instead of long Ansible/AWS CLI commands.
#
# IMPORTANT: Run from the WSL symlink path (~/devops-platform-lab), NOT from
# the Windows path (/mnt/c/...). The symlink avoids path-with-spaces issues
# that break Make's shell expansion.
#
# Prerequisites:
#   - AWS CLI configured for us-east-1
#   - community.aws Ansible collection installed
#   - WSL2 (Ubuntu) — Ansible does not support Windows as a control node
#
# Targets:
#   make deploy          — sync files to EC2 and restart the Docker Compose stack (most common)
#   make provision       — run Ansible provision.yml (first-time server setup)
#   make provision-check — dry-run provision to preview changes without applying
#   make stack-up        — start Docker Compose stack on EC2 via SSM
#   make stack-down      — stop Docker Compose stack (preserves volumes — no data loss)
#   make stack-status    — show running containers on EC2
#   make troubleshoot    — run the preflight diagnostic script

# All Ansible commands run from the Linux symlink path to avoid Windows path-with-spaces issues
ANSIBLE_DIR  := $(HOME)/devops-platform-lab/ansible
PLATFORM_DIR := $(HOME)/devops-platform-lab/platform

# EC2 instance ID — from terraform output instance_id
INSTANCE_ID  := i-0eb277f732ee785ac

# Region must match infra/variables.tf default and the Terraform S3 backend region
AWS_REGION   := us-east-1

.PHONY: troubleshoot provision-check provision deploy stack-up stack-down stack-status

# Run the preflight diagnostic script — checks Docker, AWS CLI, Ansible, and connectivity
troubleshoot:
	bash $(HOME)/devops-platform-lab/scripts/troubleshoot.sh

# Dry-run provision — shows what Ansible would change without applying anything
# Use this before running `make provision` on a live server to review the diff
provision-check:
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/provision.yml --check --diff \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml

# Full server provision — installs Docker, swap, users, firewall (idempotent)
# Only needs to run once after `terraform apply`. Safe to re-run — Ansible is idempotent.
provision:
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/provision.yml \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml

# Sync platform files to EC2 and start/restart the core stack (Jenkins, Prometheus, Grafana)
# Uses SSM to create the directory structure first, then Ansible to rsync files and start services.
# manga-hub is excluded from this deploy — it is started by the Jenkins pipeline after the
# first successful build pushes the image to GHCR.
deploy:
	@echo "Copying platform files to EC2..."
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["mkdir -p /opt/platform/jenkins/casc /opt/platform/prometheus/alerts /opt/platform/grafana/provisioning/datasources /opt/platform/grafana/provisioning/dashboards /opt/platform/grafana/dashboards"]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/deploy.yml \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml

# Start the Docker Compose stack on EC2 via SSM Run Command
# SSM is used because there is no SSH key pair — all remote commands go through AWS SSM
stack-up:
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["cd /opt/platform && docker compose up -d --build 2>&1"]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"

# Stop the stack — containers are removed but named volumes (jenkins_home, prometheus_data,
# grafana_data) are preserved. No data is lost. Use to free memory on the instance.
stack-down:
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["cd /opt/platform && docker compose down 2>&1"]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"

# Show running containers — names, status, and exposed ports
stack-status:
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\""]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"
