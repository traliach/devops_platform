# platform/jenkins/Dockerfile
# Builds the Jenkins LTS image with Docker-in-Docker support for the pipeline.
#
# Key additions on top of the base image:
#   - docker.io + docker-cli  → pipeline stages that call `docker build/push` work
#   - docker-compose standalone binary → Deploy stage runs docker-compose up directly
#   - docker-host group (GID 993) → matches the docker socket GID on the EC2 host,
#     so the jenkins user can connect to /var/run/docker.sock without running as root
#   - jenkins-plugin-cli → installs all plugins declared in plugins.txt at build time
#     (no runtime plugin download = deterministic image, faster startup)

FROM jenkins/jenkins:lts-jdk21

USER root

# Install Docker CLI tools needed by the pipeline.
# docker.io     — provides dockerd, containerd, runc (daemon components)
# docker-cli    — provides the `docker` binary (separate package on Debian trixie+)
# curl          — used by the Jenkins health check: curl -sf http://localhost:8080/login
#
# --no-install-recommends keeps the image lean by skipping optional packages.
# After install: clean apt cache and remove package lists to minimise layer size.
#
# GID 993 is the docker socket group on this EC2 instance (Amazon Linux 2023 + docker package).
# We create a matching group inside the container so the jenkins user can access the socket.
# Named docker-host (not docker) to avoid conflicting with the docker group docker.io creates.
#
# docker-compose standalone binary is installed separately because docker.io from Debian apt
# does not include the compose CLI plugin. -S = show errors, -L = follow redirects.
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    docker-cli \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 993 docker-host || true \
    && usermod -aG docker-host jenkins \
    && curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
       -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose

USER jenkins

# Copy plugin list and install all plugins at image build time.
# Running jenkins-plugin-cli here means plugins are baked into the image layer —
# Jenkins starts up immediately with all plugins ready, no download on first boot.
# Versions are intentionally unpinned — jenkins-plugin-cli resolves the latest
# versions compatible with this Jenkins LTS core at build time.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt
