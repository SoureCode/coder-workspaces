# syntax=docker/dockerfile:1

ARG BASE_IMAGE=debian:trixie-slim
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

ARG USERNAME=coder
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Base certs + gnupg so we can add the Docker apt repo.
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends --no-install-suggests && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        ca-certificates curl gnupg lsb-release && \
    rm -rf /var/lib/apt/lists/*

# Docker official apt repo (Debian).
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list

# Baseline packages + Docker engine.
RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        bash build-essential ca-certificates containerd.io curl docker-ce docker-ce-cli \
        docker-buildx-plugin docker-compose-plugin dtach file git gnupg \
        htop iproute2 iputils-ping jq less locales lsb-release lsof \
        man-db openssh-client pipx procps python3 python3-pip rsync strace \
        sudo systemd systemd-sysv tar tree unzip vim wget && \
    rm -rf /var/lib/apt/lists/*

# Pre-populate system known_hosts for common git forges so SSH clones don't
# race the agent's ssh-keyscan startup step.
RUN ssh-keyscan -t rsa,ecdsa,ed25519 github.com gitlab.com bitbucket.org \
        >> /etc/ssh/ssh_known_hosts 2>/dev/null

# Disable containerd-snapshotter so image/layer data stays under
# /var/lib/docker (classic overlay2) instead of /var/lib/containerd — the
# persistent devcontainer cache volume only covers /var/lib/docker.
RUN mkdir -p /etc/docker && \
    printf '{\n  "features": { "containerd-snapshotter": false }\n}\n' \
        > /etc/docker/daemon.json

RUN systemctl enable docker

# Classic `docker-compose` name → the compose plugin binary.
RUN ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose

# UTF-8 locale.
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Workspace user: uid 1000, in docker group, passwordless sudo.
RUN useradd "${USERNAME}" \
        --create-home \
        --shell=/bin/bash \
        --groups=docker \
        --uid=${USER_UID} \
        --user-group && \
    install -d -o "${USERNAME}" -g "${USERNAME}" -m 0755 "/home/${USERNAME}/projects" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd && \
    chmod 0440 /etc/sudoers.d/nopasswd

USER ${USERNAME}
RUN pipx ensurepath

USER root

# Contract each scripts/*/install.sh reads to target the remote user — same
# env var the devcontainer CLI used at feature-install time.
ENV _REMOTE_USER=${USERNAME}

# System-wide installers run as root.
RUN --mount=type=bind,source=scripts,target=/scripts \
    for s in context-mode home-persist; do \
      bash "/scripts/$s/install.sh"; \
    done

# Per-user installers run as the remote user directly — upstream installers
# write into $HOME with correct ownership; no root+chown dance.
USER ${USERNAME}
RUN --mount=type=bind,source=scripts,target=/scripts \
    for s in nvm claude-code rtk web-shell; do \
      bash "/scripts/$s/install.sh"; \
    done
USER root

# Coder agent: systemd unit runs /etc/coder/agent-init.sh as the workspace
# user after dockerd is up. The script itself is uploaded at container-create
# time by the Terraform template (kreuzwerker/docker `upload` block).
RUN mkdir -p /etc/coder && \
    cat > /etc/systemd/system/coder-agent.service <<EOF
[Unit]
Description=Coder Agent
After=docker.service network-online.target
Wants=network-online.target docker.service
ConditionPathExists=/etc/coder/agent-init.sh

[Service]
Type=simple
User=${USERNAME}
Group=${USERNAME}
WorkingDirectory=/home/${USERNAME}
PassEnvironment=CODER_AGENT_TOKEN
ExecStart=/bin/bash /etc/coder/agent-init.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

RUN systemctl enable coder-agent.service

CMD ["/sbin/init"]
