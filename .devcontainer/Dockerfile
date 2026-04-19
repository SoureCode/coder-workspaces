FROM debian:trixie-slim

# Preinstall nvm + Node LTS system-wide because Coder's envbuilder does not yet
# honor `overrideFeatureInstallOrder`, so the claude-code feature runs before
# our nvm feature and fails when `node` is not on PATH.
# Remove this block once https://github.com/coder/envbuilder/pull/500 is
# merged and released (tracks `overrideFeatureInstallOrder` support).
ENV NVM_DIR=/usr/local/share/nvm
ENV NVM_VERSION=0.40.4
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p "$NVM_DIR"; \
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash; \
    . "$NVM_DIR/nvm.sh"; \
    nvm install --lts; \
    nvm alias default 'lts/*'; \
    NODE_BIN_DIR="$(dirname "$(nvm which default)")"; \
    for bin in node npm npx corepack; do \
      [ -x "$NODE_BIN_DIR/$bin" ] && ln -sf "$NODE_BIN_DIR/$bin" "/usr/local/bin/$bin"; \
    done; \
    printf 'export NVM_DIR="%s"\n[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\n[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"\n' "$NVM_DIR" >/etc/profile.d/nvm.sh; \
    chmod 644 /etc/profile.d/nvm.sh
