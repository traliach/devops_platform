# devops-platform-lab — Build Runbook

**Author:** Achille Traore | achille.tech
**Started:** 2026-04-01
**Goal:** Self-hosted DevOps platform on AWS EC2 — Jenkins CI/CD, Prometheus, Grafana,
deployed via Docker Compose, provisioned with Terraform, configured with Ansible.

This runbook documents every build step in order: what was done, why it was done,
and the exact commands used. It serves as both an operational reference and a
portfolio record of the decisions made during construction.

---

## Cost target

- Instance: `t3.small` (minimum for Jenkins — 2 GB RAM required)
- Budget: ~$5/month (~238 hours of runtime — stop the instance when not working)
- Strategy: stop the EC2 instance when not actively working; never terminate (state preserved on EBS)
- Free-tier components: S3 (Terraform state), DynamoDB (state lock), VPC, subnets, security groups, IAM, SSM

---

## Architecture summary

```
GitHub → GitHub Actions (CI/CD validation)
            ↓
        AWS EC2 t3.small (us-east-1)
            ↓ provisioned by Terraform
            ↓ configured by Ansible
            ↓
        Docker Compose stack
        ├── Jenkins LTS        (CI/CD — builds & deploys Flask app)
        ├── Prometheus         (metrics scraping — Jenkins + Flask app + node)
        ├── Grafana            (dashboards — pipeline health + app performance)
        └── Flask app          (sample Python app — the thing being deployed)
```

---

## Sprints

Each sprint delivers something runnable and testable end-to-end.

---

### Sprint 0 — Prerequisites
**Goal:** All tooling, secrets, and AWS bootstrap resources in place before any Terraform runs.
**Deliverable:** `bash scripts/setup-prerequisites.sh` completes without errors.

| Step | Task | Status |
|------|------|--------|
| 0.1 | `scripts/setup-prerequisites.sh` — creates DynamoDB lock table, SSH key, detects IP, sets GitHub secrets | done |

**Key decisions:**
- DynamoDB table named `devops-platform-lab-tf-lock` (project-scoped, not shared)
- Created via AWS CLI **before** `terraform init` — avoids chicken-egg problem
- S3 bucket (`achille-tf-state`) already exists and is reused across projects with different state keys
- SSH key is optional — primary access is via AWS SSM Session Manager (no fixed IP needed)

---

### Sprint 1 — Infrastructure (Terraform)
**Goal:** EC2 instance running and reachable via SSM Session Manager.
**Deliverable:** `terraform apply` produces a live server with a stable public IP.
**Status: COMPLETE — 2026-04-02** ✓

| Step | Task | Status |
|------|------|--------|
| 1.1 | `infra/variables.tf` — all input variables | done |
| 1.2 | `infra/main.tf` — AWS provider + S3 remote backend + DynamoDB state lock | done |
| 1.3 | `infra/networking.tf` — VPC, subnet, IGW, security group, Elastic IP | done |
| 1.4 | `infra/iam.tf` — IAM role + SSM policy + instance profile | done |
| 1.5 | `infra/ec2.tf` — EC2 t3.small, AMI data source, optional key pair, prevent_destroy | done |
| 1.6 | `infra/outputs.tf` — public IP, instance ID, SSH/SSM/stop/start commands | done |

**Issue encountered:** First `apply` failed — AL2023 AMI snapshot requires minimum 30GB root volume.
`variables.tf` default was 20GB. Fixed to 30GB before re-applying.

**Key decisions:**

_variables.tf_
- `allowed_ssh_cidrs` is a **list** (not a single string) — supports home + work + hotspot IPs
- `public_key` is **optional** (default null) — SSH is a fallback, not the primary access method

_main.tf_
- S3 backend reuses `achille-tf-state` bucket with key `devops-platform-lab/terraform.tfstate`
- `dynamodb_table = "devops-platform-lab-tf-lock"` — prevents concurrent `terraform apply` runs
- `encrypt = true` — state file encrypted at rest in S3

_networking.tf_
- SSH (22), Jenkins (8080), Grafana (3000) locked to `allowed_ssh_cidrs` — never `0.0.0.0/0`
- HTTP (80) and HTTPS (443) open publicly — Nginx reverse proxy handles routing
- Prometheus (9090) and Flask (5000) have no public ingress rules — internal only
- Elastic IP ensures the public IP is stable across stop/start cycles

_iam.tf_
- `AmazonSSMManagedInstanceCore` policy attached — enables SSM Session Manager
- No AWS access keys stored on the server — IAM role is the correct pattern

_ec2.tf_
- AMI resolved via `data "aws_ami"` — never hardcoded (always latest Amazon Linux 2023)
- `aws_key_pair` resource created only when `var.public_key != null` (count = 0 or 1)
- `prevent_destroy = true` — use stop/start for cost control, not destroy
- Root volume: gp3, 20GB, encrypted

_outputs.tf_
- SSH command output adapts: shows SSH command if key pair exists, SSM command if not

**Why there is no key pair — and why that is correct**

Traditional EC2 access requires:
1. An SSH key pair stored in AWS
2. Port 22 open in the security group
3. A fixed IP to lock down that port

This creates two problems for a real DevOps workflow:
- Your IP changes (home → work → hotspot → travel) and you'd be locked out
- An open SSH port is an attack surface, even when restricted to your IP

**AWS Systems Manager Session Manager** solves both. It works by:
- The EC2 instance runs the SSM Agent (pre-installed on Amazon Linux 2023)
- The `AmazonSSMManagedInstanceCore` IAM policy we attached gives the agent permission to register with SSM
- You connect through the AWS API — not through a network port
- Port 22 does not need to be open. The connection is encrypted via AWS APIs
- Works from any network, anywhere in the world, with no IP restriction
- All session activity is logged in AWS CloudTrail automatically

This is the modern, security-hardened way to access EC2 instances. SSH + key pairs are legacy at this point for single-instance lab work.

**Commands run:**
```bash
terraform init
terraform plan -out=tfplan
# Fixed: AL2023 AMI requires minimum 30GB root volume (default was 20GB)
# Updated variables.tf default to 30GB — root cause was AWS updating the AMI snapshot
terraform apply -auto-approve
```

**Apply output — Sprint 1 complete (2026-04-02):**
```
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

instance_id   = "i-0eb277f732ee785ac"
public_ip     = "54.159.150.73"
ssh_command   = "No key pair — connect via: aws ssm start-session --target i-0eb277f732ee785ac --region us-east-1"
stop_command  = "aws ec2 stop-instances --instance-ids i-0eb277f732ee785ac --region us-east-1"
start_command = "aws ec2 start-instances --instance-ids i-0eb277f732ee785ac --region us-east-1"
```

To connect to the instance:
```bash
aws ssm start-session --target i-0eb277f732ee785ac --region us-east-1
```

---

### Sprint 2 — Server Configuration (Ansible)
**Goal:** EC2 instance has Docker, a deploy user, and firewall rules — ready to run the platform.
**Deliverable:** `ansible-playbook provision.yml` runs idempotently end-to-end.

| Step | Task | Status |
|------|------|--------|
| 2.1 | `ansible/ansible.cfg` + `inventory/hosts.ini` | done |
| 2.2 | `roles/common` — base packages, timezone, swap, sysctl | done |
| 2.3 | `roles/docker` — Docker CE + Compose plugin | done |
| 2.4 | `roles/users` — deploy user, scoped sudoers | done |
| 2.5 | `roles/firewall` — firewalld (AL2023 native) | done |
| 2.6 | `playbooks/provision.yml` + `deploy.yml` | done |
| 2.7 | `ansible/requirements.yml` — pinned galaxy collections | done |

**Key decisions:**

_Connection method — SSM, not SSH_
- `ansible.cfg` uses `community.aws.aws_ssm` connection plugin
- Ansible connects to EC2 via AWS SSM Run Command — no port 22, no key pair needed
- Consistent with the Terraform decision: SSM is the only access method for this project
- Requires `boto3`, `botocore`, and the `community.aws` collection installed on the control node

_firewalld, not UFW_
- The runbook spec mentioned UFW, but UFW is an Ubuntu/Debian tool
- Amazon Linux 2023 is RHEL-based — `firewalld` is the native and correct firewall tool
- UFW is not available in the AL2023 package repos
- Docker note: Docker manages its own iptables rules and can bypass firewalld — the AWS security group remains the authoritative firewall for container ports; firewalld is a defense-in-depth layer for host services only

_Deploy user sudoers — scoped, not full sudo_
- The deploy user only has passwordless sudo for `/usr/bin/docker` and `/usr/bin/docker compose`
- Full sudo would be a security risk — Jenkins only needs to run Docker commands

_Swap — 2GB on t3.small_
- Jenkins is memory-hungry and will OOM-kill without swap on a 2GB instance
- `vm.swappiness = 10` means the kernel uses swap only when RAM is nearly full, not aggressively

---

**Q&A — questions raised during Sprint 2:**

**Q: Why can't I run Ansible on my Windows laptop (Git Bash)?**
A: Ansible uses `os.get_blocking()` — a Linux-only system call. It hard-fails on Windows with
`OSError: [WinError 1] Incorrect function`. This is a known, permanent limitation.
Ansible does not support Windows as a control node — only as a managed node.

**Q: So where do I run Ansible from?**
A: Three options:
1. **WSL (recommended)** — installs a real Ubuntu environment on your Windows machine.
   Run all Ansible/DevOps tooling from there. One-time setup, 15 minutes.
   ```powershell
   # PowerShell as Administrator:
   wsl --install
   ```
2. **EC2 itself (quick workaround)** — SSM into the instance, install Ansible there,
   run the playbook against `localhost`. The server configures itself. Not standard but works.
3. **GitHub Actions (most automated)** — Ansible runs on Ubuntu CI runners on every push.
   No local tooling needed. Best long-term approach.

**Decision:** WSL chosen — correct control node setup, required for interview credibility,
needed for the rest of the project (Ansible, docker CLI testing, shellcheck, etc.).

**Q: What is the Ansible control node vs managed node?**
A:
```
CONTROL NODE (your laptop / WSL)     MANAGED NODE (EC2 instance)
────────────────────────────────     ───────────────────────────
You write playbooks here             Ansible configures this remotely
You run ansible-playbook here  ───►  Tasks execute here
Must be Linux or Mac                 Any Linux — Ansible not required here
```
Ansible is only installed on the control node. It connects to managed nodes
remotely (via SSH or SSM) and executes tasks there. The EC2 instance never
needs Ansible installed.

---

---

**Issues encountered and resolved — Sprint 2 (2026-04-02)**

---

**Issue 1 — Ansible cannot run on Windows (Git Bash)**

_Symptom:_
```
OSError: [WinError 1] Incorrect function
```
_Root cause:_ Ansible calls `os.get_blocking()` — a Linux-only system call. This is a
hard, permanent limitation. Ansible does not support Windows as a control node.

_Fix:_ Install WSL2 (Ubuntu 24.04) on Windows and run all Ansible commands from there.
```powershell
# PowerShell as Administrator (64-bit, not x86):
wsl --install -d Ubuntu
```
_Lesson:_ Always run DevOps tooling (Ansible, Terraform, shellcheck) from a Linux environment.
On Windows, WSL is the correct and supported solution.

---

**Issue 2 — ansible-playbook not found after pip install**

_Symptom:_ `Command 'ansible-playbook' not found` even after `pip install ansible`

_Root cause:_ Ubuntu 24.04 protects system Python with PEP 668. `pip install` into the
system Python is blocked. The binary was installed via `pipx` but PATH was not refreshed.

_Fix:_ Install via `sudo apt install ansible-core` instead — uses system package manager,
no PATH issues.

---

**Issue 3 — ansible.cfg ignored (world-writable directory warning)**

_Symptom:_
```
[WARNING]: Ansible is being run in a world writable directory, ignoring it as an ansible.cfg source
```
_Root cause:_ Windows NTFS mounts (`/mnt/c/...`) appear world-writable to Linux.
Ansible refuses to load `ansible.cfg` from these paths as a security measure.

_Fix 1 (short term):_ Pass config explicitly via environment variables:
```bash
ANSIBLE_CONFIG="..." ANSIBLE_ROLES_PATH="..." ansible-playbook ...
```
_Fix 2 (long term):_ Create a symlink in the Linux filesystem:
```bash
ln -s "/mnt/c/Users/trach/Documents/New project/devops_platform" ~/devops-platform-lab
```
Run all commands from `~/devops-platform-lab` — Linux filesystem, no world-writable warning.
A `Makefile` was added to wrap the commands so they never need to be typed in full.

---

**Issue 4 — Makefile cannot handle spaces in paths**

_Symptom:_ `cd: can't cd to /mnt/c/Users/trach/Documents/New`

_Root cause:_ Make splits on spaces. The project directory "New project" contains a space.
Even with quoting, Make's shell expansion strips quotes before `cd` sees them.

_Fix:_ Use `$(HOME)/devops-platform-lab` (the symlink) in the Makefile — no spaces in path.

---

**Issue 5 — Docker CE RHEL repo incompatible with AL2023**

_Symptom:_
```
Status code: 404 for https://download.docker.com/linux/rhel/2023.10.../repodata/repomd.xml
No package docker-ce available.
No package docker-ce-cli available.
```
_Root cause:_ Amazon Linux 2023 is Fedora-based, not RHEL. Docker's RHEL repo uses
the OS version string (`2023.10.20260325`) as the repo path, which does not exist on
Docker's CDN. The repo file was written to the instance during a failed Ansible run
and continued poisoning `dnf` on every subsequent attempt — even after we fixed the
Ansible role, the bad file was already on the server.

_Fix (immediate):_ Remove the bad repo file directly via SSM Run Command:
```bash
aws ssm send-command \
  --instance-ids "i-0eb277f732ee785ac" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["rm -f /etc/yum.repos.d/docker-ce.repo && dnf clean all"]' \
  --region us-east-1 \
  --query "Command.CommandId" --output text
```
_Fix (in Ansible):_ Updated `roles/docker/tasks/main.yml` to:
1. Explicitly remove `/etc/yum.repos.d/docker-ce.repo` at the start of the role (idempotent)
2. Install `docker` from Amazon's native AL2023 repos (package name: `docker`, not `docker-ce`)
3. Install Docker Compose as a standalone binary from GitHub releases (not available in AL2023 repos)

_Lesson:_ Amazon Linux 2023 is NOT a drop-in RHEL replacement for third-party repos.
Always use Amazon's native packages when available. Never assume Docker CE RHEL repos work on AL2023.

---

**Issue 6 — `firewall-cmd --set-default-zone=drop --permanent` fails**

_Symptom:_
```
Can't use stand-alone options with other options.
rc: 2
```
_Root cause:_ `--set-default-zone` is documented as a standalone command in firewalld.
It is already both a runtime and permanent change — adding `--permanent` is invalid
and conflicts with it. The firewalld man page lists many commands as `[--permanent] ...`
but `--set-default-zone` is not one of them.

_Fix:_ Remove `--permanent`:
```yaml
- name: Set default zone to drop
  command: firewall-cmd --set-default-zone=drop
```

_Additional fix:_ Removed the "Allow established connections" rich rule:
```yaml
# REMOVED — this was wrong:
- name: Allow established connections
  firewalld:
    rich_rule: "rule family=ipv4 source address=0.0.0.0/0 accept"
```
This rule did NOT mean "established connections only" — it meant "allow all IPv4 sources",
effectively opening the firewall completely. firewalld is stateful by default — return
traffic for outbound connections is implicitly allowed. No rich rule needed.

---

**Sprint 2 final result — 2026-04-02**
```
PLAY RECAP
i-0eb277f732ee785ac : ok=23  changed=2  unreachable=0  failed=0  skipped=4  rescued=0  ignored=0
```
Server state after Sprint 2:
- Base packages installed (git, vim, wget, htop, jq, python3)
- Timezone: UTC
- Swap: 2GB enabled and persisted in fstab
- sysctl tuned (vm.swappiness=10, vm.dirty_ratio=15, net.core.somaxconn=1024)
- Docker 25.0.14 running, Compose plugin installed at `/usr/libexec/docker/cli-plugins/`
- `deploy` user created, in docker group, scoped sudo for docker only
- firewalld running, default zone: drop, ports 80/443/8080/3000 open

---

### Sprint 3 — Platform Stack (Docker Compose + Jenkins)
**Goal:** Jenkins, Prometheus, and Grafana running as containers on the EC2 instance.
**Deliverable:** All services accessible, Jenkins configured via JCasC (no manual UI setup).
**Status: COMPLETE — 2026-04-04** ✓

| Step | Task | Status |
|------|------|--------|
| 3.1 | `platform/docker-compose.yml` — all services with health checks, limits, named volumes | done |
| 3.2 | `platform/.env` — all required env vars filled in | done |
| 3.3 | `platform/jenkins/Dockerfile` — Jenkins LTS + Docker CLI + plugins | done |
| 3.4 | `platform/jenkins/plugins.txt` — pinned plugin list compatible with Jenkins 2.452.3 | done |
| 3.5 | `platform/jenkins/casc/jenkins.yaml` — full JCasC configuration | done |
| 3.6 | `ansible/playbooks/deploy.yml` — copies full platform directory, pulls images, starts stack | done |
| 3.7 | `scripts/fix-and-deploy.sh` — 7-check preflight script, auto-fixes known issues, then deploys | done |

---

**Issues encountered and resolved — Sprint 3 (2026-04-03 → 2026-04-04)**

---

**Issue 1 — `become_user: deploy` fails over SSM connection**

_Symptom:_
```
Failed to set permissions on the temporary files Ansible needs to create when
becoming an unprivileged user (rc: 1, err: })
```

_Root cause:_ `deploy.yml` used `become_user: deploy` on the `docker compose pull` and
`docker compose up` tasks. The SSM connection plugin connects as root — privilege
escalation _down_ to an unprivileged user requires ACL/tempfile support that is not
available in the SSM session environment.

_Fix:_ Remove `become_user: deploy` from the docker tasks. The SSM connection already
runs as root via `become: true` at the play level. Root can run docker commands directly.
The `deploy` user's docker group membership is only relevant for interactive sessions,
not for Ansible-driven deploys.

```yaml
# BEFORE (broken):
- name: Pull latest images
  command: docker compose pull
  args:
    chdir: /opt/platform
  become_user: "{{ deploy_user }}"   # <-- causes ACL error over SSM

# AFTER (working):
- name: Pull latest images
  command: docker compose pull
  args:
    chdir: /opt/platform
  # No become_user — SSM already runs as root
```

---

**Issue 2 — `make deploy` ran from wrong region**

_Symptom:_
```
aws: [ERROR]: An error occurred (InvalidInstanceID.NotFound) when calling the
DescribeInstances operation: The instance ID 'i-0eb277f732ee785ac' does not exist
```

_Root cause:_ Early troubleshooting commands were written with `--region eu-west-3`
(a copy-paste artifact). The project was deployed to `us-east-1`. The instance existed
but in a different region — AWS returns "not found" across regions, not "wrong region".

_Fix:_ Corrected all AWS CLI commands and scripts to use `--region us-east-1`, consistent
with `infra/variables.tf` default and `infra/main.tf` backend config.

_Lesson:_ Always verify the region in `infra/variables.tf` (`default = "us-east-1"`)
before running any AWS CLI command. The Terraform state bucket and EC2 instance must be
in the same region as the CLI target.

---

**Issue 3 — `docker compose up --build` requires buildx >= 0.17.0**

_Symptom:_
```
Image platform-jenkins Building
compose build requires buildx 0.17.0 or later
```

_Root cause:_ Amazon Linux 2023's native `docker` package ships with an older version of
buildx that predates the 0.17.0 requirement introduced by Docker Compose v2.29+. We
install the latest Docker Compose binary from GitHub releases, but the bundled buildx
plugin comes from the Amazon package and is too old.

_Fix:_ Add a task to the Ansible `docker` role that installs the latest `docker-buildx`
binary from GitHub releases alongside the Compose plugin:

```yaml
- name: Install Docker buildx plugin (latest)
  shell: |
    set -e
    VERSION=$(curl -sf "https://api.github.com/repos/docker/buildx/releases/latest" \
      | grep '"tag_name"' | cut -d'"' -f4)
    curl -sfL "https://github.com/docker/buildx/releases/download/${VERSION}/buildx-${VERSION}.linux-amd64" \
      -o /usr/libexec/docker/cli-plugins/docker-buildx
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
```

For the live instance (already provisioned), this was applied directly via SSM using
`scripts/install-buildx.json`.

_Lesson:_ When mixing Amazon Linux native packages with GitHub-released binaries, always
check version compatibility. Install both Compose and buildx from GitHub to guarantee
version alignment.

---

**Issue 4 — SSM connection drops during `docker compose up` (timeout)**

_Symptom:_
```
fatal: [i-0eb277f732ee785ac]: UNREACHABLE! => changed=false
  msg: 'SSM exec_command timeout on host: i-0eb277f732ee785ac'
```

_Root cause:_ The SSM connection plugin holds a single long-running connection per task.
`docker compose up --build` can take 3–5 minutes to build the Jenkins image and pull the
other images — longer than the SSM session idle timeout.

_Fix:_ Use Ansible `async` + `poll` so each poll is a fresh, short-lived SSM call instead
of one blocking connection:

```yaml
- name: Build and start stack
  command: docker compose up -d --remove-orphans --build
  args:
    chdir: /opt/platform
  async: 600   # allow up to 10 minutes total
  poll: 20     # check every 20 seconds (new SSM call each time)
```

---

**Issue 5 — DNS broken inside Docker build containers**

_Symptom:_
```
#7 240.7 W: Failed to fetch http://deb.debian.org/debian/dists/bookworm/InRelease
             Temporary failure resolving 'deb.debian.org'
E: Unable to locate package docker.io
```

_Root cause:_ The Docker daemon on the EC2 instance was not configured with explicit DNS
servers. By default, Docker containers inherit the host's DNS resolver. On Amazon Linux 2023,
the default DNS resolver is `169.254.169.253` (the AWS VPC resolver). This works for the
host, but Docker containers run in a different network namespace and cannot reach it.
Build containers that try to run `apt-get update` cannot resolve any Debian mirror hostnames.

_Fix:_ Configure the Docker daemon to use Google's public DNS servers for all containers:

```json
// /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "storage-driver": "overlay2",
  "dns": ["8.8.8.8", "8.8.4.4"]
}
```

Applied on the live instance via `scripts/fix-docker-dns.json` (SSM Run Command).
Also added to `roles/docker/tasks/main.yml` for future provisions.

Verified with:
```bash
docker run --rm alpine nslookup deb.debian.org
# Expected: DNS_OK
```

_Lesson:_ Docker containers on EC2 do not automatically inherit the VPC resolver. Always
set `"dns"` explicitly in `daemon.json` for instances that need to build images that do
`apt-get`, `yum`, or any package install.

---

**Issue 6 — Jenkins plugin install fails: bad Prometheus version pin**

_Symptom:_
```
failed to solve: process "/bin/sh -c jenkins-plugin-cli --plugin-file
/usr/share/jenkins/ref/plugins.txt" did not complete successfully: exit code: 1
```

_Root cause:_ `plugins.txt` had `prometheus:777.v4f3f5e4b_76e0`. This version does not
exist on the official Jenkins plugin update center. `jenkins-plugin-cli` exits with code 1
(no verbose output by default) when it cannot locate a pinned version, making the error
hard to identify without the `--verbose` flag.

> **Note:** This root cause was identified with the help of an external AI assistant
> (GPT-4o) after `--verbose` output was provided. The assistant confirmed that
> `prometheus:777.v4f3f5e4b_76e0` does not appear on the Jenkins plugin release pages,
> while `prometheus:779.vb_59179a_27643` does.

_Fix:_
```diff
# platform/jenkins/plugins.txt
-prometheus:777.v4f3f5e4b_76e0
+prometheus:779.vb_59179a_27643
```

Also added `--verbose --latest=false` to the Dockerfile to expose future failures clearly:
```dockerfile
RUN jenkins-plugin-cli --verbose --latest=false \
    --plugin-file /usr/share/jenkins/ref/plugins.txt
```

---

**Issue 7 — Jenkins plugin install fails: credentials-binding too new for Jenkins 2.452.3**

_Symptom (from `--verbose` output):_
```
credentials-binding:687.v619cb_15e923f requires Jenkins 2.479
credentials:1381.v2c3a_12074da_b_ requires Jenkins 2.462.3
configuration-as-code:1810... wants configuration-as-code:1836...
```

_Root cause:_ Three plugin pins were for versions that require a newer Jenkins core than
`2.452.3-lts`:
- `credentials-binding:687.v619cb_15e923f` → requires Jenkins 2.479
- `credentials` (transitive dep) → version resolved was too new for 2.452.3
- `configuration-as-code:1810.v9b_c30a_249a_4c` → triggered a conflict with its own
  transitive dependencies

> **Note:** This resolution was identified by an external AI assistant (GPT-4o), which
> cross-referenced the Jenkins plugin release pages to find versions compatible with
> Jenkins 2.452.3 LTS.

_Fix:_ Downgrade the three conflicting pins to versions that line up with Jenkins 2.452.3:

```diff
# platform/jenkins/plugins.txt
-configuration-as-code:1810.v9b_c30a_249a_4c
+configuration-as-code:1775.v810dc950b_514

-credentials-binding:687.v619cb_15e923f
+credentials-binding:677.vdc9d38cb_254d

+credentials:1337.v60b_d7b_c7b_c9f   # explicit pin to prevent auto-resolution to incompatible version
```

_Lesson:_ When pinning Jenkins plugins, always verify the "Required Core" field on the
plugin's release page against your Jenkins LTS version. Plugin version numbers in Jenkins
often embed the Jenkins core version requirement in the name (e.g. `687` → requires ~2.479).
The `--latest=false` flag in `jenkins-plugin-cli` is essential — without it the CLI may
silently resolve a newer version and break the build.

---

**Sprint 3 final result — 2026-04-04**
```
PLAY RECAP
i-0eb277f732ee785ac : ok=6  changed=4  unreachable=0  failed=0  skipped=0  rescued=0  ignored=0
```

Stack state after Sprint 3:
- Jenkins, Prometheus, and Grafana containers running on EC2
- Jenkins image built from custom Dockerfile with Docker CLI and pinned plugins
- Jenkins configured via JCasC — no manual UI wizard
- Prometheus scraping Jenkins metrics at `:8080/prometheus`
- Grafana provisioned with Prometheus datasource
- Flask app service commented out in `docker-compose.yml` — built and pushed in Sprint 4
- All deploy steps automated via `make deploy` (wrapped by `scripts/fix-and-deploy.sh` for preflight checks)

---

### Sprint 4 — Flask Application + Jenkins Pipeline
**Goal:** Jenkins automatically builds, tests, and deploys the Flask app on every push to main.
**Deliverable:** Passing Jenkins pipeline — Checkout → Test → Build → Push → Deploy.

| Step | Task | Status |
|------|------|--------|
| 4.1 | `app/src/app.py` — Flask app with `/`, `/health`, `/metrics` endpoints | pending |
| 4.2 | `app/Dockerfile` — multi-stage, non-root, Python 3.12-alpine | pending |
| 4.3 | `app/requirements.txt` — pinned dependencies | pending |
| 4.4 | `app/tests/test_app.py` — pytest (health + metrics endpoints) | pending |
| 4.5 | `app/Jenkinsfile` — declarative pipeline (Checkout → Test → Build → Push → Deploy) | pending |

---

### Sprint 5 — Observability (Prometheus + Grafana)
**Goal:** Live dashboards showing Jenkins pipeline health and Flask app performance.
**Deliverable:** Two working Grafana dashboards fed by Prometheus scrape data.

| Step | Task | Status |
|------|------|--------|
| 5.1 | `platform/prometheus/prometheus.yml` — scrape configs (Jenkins + Flask + node_exporter) | pending |
| 5.2 | `platform/grafana/provisioning/datasources/prometheus.yaml` — auto-provision datasource | pending |
| 5.3 | `platform/grafana/provisioning/dashboards/dashboards.yaml` — dashboard provisioning config | pending |
| 5.4 | `platform/grafana/dashboards/jenkins.json` — pipeline success rate, build duration, queue depth | pending |
| 5.5 | `platform/grafana/dashboards/flask-app.json` — request rate, error rate, p95 latency | pending |

---

### Sprint 6 — Automation, CI/CD & Docs
**Goal:** Everything is automated, validated by CI, and documented for handoff.
**Deliverable:** GitHub Actions green on main, runbook complete, README with architecture diagram.

| Step | Task | Status |
|------|------|--------|
| 6.1 | `scripts/bootstrap.sh` — first-time local setup helper | pending |
| 6.2 | `scripts/health-check.sh` — validates EC2 + Docker + all 4 services | pending |
| 6.3 | `scripts/backup.sh` — Jenkins home + Prometheus + Grafana data | pending |
| 6.4 | `scripts/rotate-logs.sh` — log rotation helper | pending |
| 6.5 | `.github/workflows/ci.yml` — terraform validate + ansible-lint + pytest + shellcheck + docker build | pending |
| 6.6 | `.github/workflows/release.yml` — tag + GHCR push + GitHub release | pending |
| 6.7 | `docs/architecture.png` — architecture diagram | pending |
| 6.8 | `README.md` — full setup, deploy, and architecture documentation | pending |

---

## Operational reference

### Connect to the instance (SSM — works from any network)

```bash
# Get instance ID from Terraform output
terraform -chdir=infra output instance_id

# Connect via SSM (no port 22, no fixed IP required)
aws ssm start-session --target <instance-id> --region us-east-1

# Or use the ready-made output
$(terraform -chdir=infra output -raw ssh_command)
```

### Start / stop the instance (cost control)

```bash
# Stop instance (preserves EBS — only storage costs while stopped)
$(terraform -chdir=infra output -raw stop_command)

# Start instance
$(terraform -chdir=infra output -raw start_command)

# Elastic IP stays the same — no IP update needed after start
terraform -chdir=infra output public_ip
```

### Full teardown (when project is complete)

```bash
# 1. Remove prevent_destroy from infra/ec2.tf
# 2. Then:
terraform -chdir=infra destroy
# 3. Optionally delete the DynamoDB lock table:
aws dynamodb delete-table --table-name devops-platform-lab-tf-lock --region us-east-1
```

### Check all services are running

```bash
bash scripts/health-check.sh
```
