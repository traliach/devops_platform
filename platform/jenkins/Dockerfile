FROM jenkins/jenkins:lts-jdk21

USER root
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
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt