ANSIBLE_DIR  := $(HOME)/devops-platform-lab/ansible
PLATFORM_DIR := $(HOME)/devops-platform-lab/platform
INSTANCE_ID  := i-0eb277f732ee785ac
AWS_REGION   := us-east-1

.PHONY: troubleshoot provision-check provision deploy stack-up stack-down stack-status

troubleshoot:
	bash $(HOME)/devops-platform-lab/scripts/troubleshoot.sh

provision-check:
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/provision.yml --check --diff \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml

provision:
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/provision.yml \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml

# Copy platform files to EC2 and start the stack
deploy:
	@echo "Copying platform files to EC2..."
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["mkdir -p /opt/platform/jenkins/casc /opt/platform/prometheus /opt/platform/grafana/provisioning/datasources /opt/platform/grafana/provisioning/dashboards /opt/platform/grafana/dashboards"]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/deploy.yml \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml

# Start the Docker Compose stack on EC2 via SSM
stack-up:
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["cd /opt/platform && docker compose up -d --build 2>&1"]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"

# Stop the stack (cost control — stops containers, not the instance)
stack-down:
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["cd /opt/platform && docker compose down 2>&1"]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"

# Check running containers on EC2
stack-status:
	@aws ssm send-command \
	  --instance-ids "$(INSTANCE_ID)" \
	  --document-name "AWS-RunShellScript" \
	  --parameters 'commands=["docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\""]' \
	  --region $(AWS_REGION) --output text --query "Command.CommandId"
