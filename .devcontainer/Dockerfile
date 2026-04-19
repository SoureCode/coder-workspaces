FROM debian:trixie-slim

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN apt-get update \
    && apt-get install -y --no-install-recommends sudo ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"${USERNAME}" \
    && chmod 0440 /etc/sudoers.d/"${USERNAME}"

USER ${USERNAME}
