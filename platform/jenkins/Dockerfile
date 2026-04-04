# Jenkins LTS — pinned version, never weekly releases
# Plugins installed at build time from plugins.txt — never auto-update at runtime
FROM jenkins/jenkins:2.452.3-lts-jdk17

# Switch to root to install system dependencies
USER root

# Install Docker CLI so Jenkins can build and push images
RUN apt-get update && apt-get install -y \
    docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch back to jenkins user — never run Jenkins as root
USER jenkins

# Copy pinned plugin list and install at build time
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --verbose --latest=false --plugin-file /usr/share/jenkins/ref/plugins.txt

# JCasC config is mounted at runtime via volume — see docker-compose.yml
# CASC_JENKINS_CONFIG env var points Jenkins to /var/jenkins_home/casc
