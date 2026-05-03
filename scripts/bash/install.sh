#!/usr/bin/env bash
# Bash history installer. Runs as root.
# - Drops history configuration into /etc/profile.d/ so every interactive shell
#   (login and non-login) picks it up.
# - Strips the skeleton ~/.bashrc history block so it cannot override system values.
# - Registers .bash_history with home-persist so it survives workspace rebuilds.
set -eo pipefail

cat > /etc/profile.d/bash-history.sh <<'PROF'
if [ -z "${__BASH_HIST_CONFIGURED:-}" ]; then
  __BASH_HIST_CONFIGURED=1
  HISTCONTROL=ignoreboth
  HISTSIZE=10000
  HISTFILESIZE=20000
  shopt -s histappend
  PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND};}history -a; history -n"
fi
PROF

patch_bashrc() {
  local file="$1"
  [ -f "$file" ] || return 0

  sed -i '/^# .*history/d' "$file"

  if grep -q '^HISTCONTROL=' "$file"; then
    sed -i 's/^HISTCONTROL=.*/HISTCONTROL=ignoreboth/' "$file"
  else
    echo 'HISTCONTROL=ignoreboth' >> "$file"
  fi

  if grep -q '^HISTSIZE=' "$file"; then
    sed -i 's/^HISTSIZE=.*/HISTSIZE=10000/' "$file"
  else
    echo 'HISTSIZE=10000' >> "$file"
  fi

  if grep -q '^HISTFILESIZE=' "$file"; then
    sed -i 's/^HISTFILESIZE=.*/HISTFILESIZE=20000/' "$file"
  else
    echo 'HISTFILESIZE=20000' >> "$file"
  fi

  if grep -q '^shopt -s histappend' "$file"; then
    sed -i '/^shopt -s histappend/d' "$file"
  fi
}

patch_bashrc /etc/skel/.bashrc

home="${_REMOTE_USER:+/home/${_REMOTE_USER}}"
[ -n "$home" ] && patch_bashrc "$home/.bashrc"

mkdir -p /etc/home-persist.d
cat > /etc/home-persist.d/bash.json <<'EOF'
{
  "source": "bash",
  "paths": [".bash_history"]
}
EOF
