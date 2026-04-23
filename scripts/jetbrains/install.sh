#!/usr/bin/env bash
# jetbrains installer.
#
# How the Coder JetBrains flow works: the workspace is headless. Clicking the
# IDE button in the Coder UI opens a `jetbrains-gateway://` URL that the
# user's *local* Toolbox/Gateway handles; Gateway then SSHes into the
# workspace and runs remote-dev-server.sh, which downloads the IDE backend
# (IntelliJ IDEA, PyCharm, CLion, WebStorm, GoLand, RubyMine, PhpStorm,
# Rider, DataGrip) on-demand into $HOME. Toolbox itself never runs on the
# workspace. Nothing to install in the image — this script only declares the
# HOME paths the remote-dev backend writes, so Gateway doesn't redownload
# hundreds of MB and users don't lose settings, plugins, and project indexes
# on every restart.
#
# JetBrains' remote-dev backend follows the XDG scheme on Linux with a
# RemoteDev-<Code> subdir per IDE flavor (PS = PhpStorm, PY = PyCharm, IU =
# IDEA Ultimate, CL = CLion, ...) under these three roots:
#
#   ~/.cache/JetBrains/         — RemoteDev/dist/<build>/ (downloaded backend),
#                                 RemoteDev-<Code>/ system caches, indexes,
#                                 LocalHistory, log
#   ~/.config/JetBrains/        — RemoteDev-<Code>/ IDE settings, keymaps,
#                                 schemes, options, workspace, .lock
#   ~/.local/share/JetBrains/   — RemoteDev-<Code>/ installed plugins,
#                                 Daemon, consentOptions
#
# Plus the Java Preferences store the IDEs use for JetBrains Account
# (JetProfile) login, license activation, and non-commercial-license
# acceptance — skipping this forces re-login + re-accept every restart:
#
#   ~/.java/.userPrefs/jetbrains/
set -e

mkdir -p /etc/home-persist.d
tee /etc/home-persist.d/jetbrains.json >/dev/null <<'EOF'
{
  "source": "jetbrains",
  "paths": [
    ".cache/JetBrains/",
    ".config/JetBrains/",
    ".local/share/JetBrains/",
    ".java/.userPrefs/jetbrains/"
  ]
}
EOF
