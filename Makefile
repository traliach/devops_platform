ANSIBLE_DIR := $(HOME)/devops-platform-lab/ansible

.PHONY: provision provision-check deploy troubleshoot

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

deploy:
	cd "$(ANSIBLE_DIR)" && \
	ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
	ANSIBLE_ROLES_PATH="$(ANSIBLE_DIR)/roles" \
	ansible-playbook playbooks/deploy.yml \
	  -i inventory/hosts.ini \
	  -e @group_vars/all/vars.yml
