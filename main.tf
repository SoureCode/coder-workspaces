terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

locals {
  workspace_user = "coder"
  workspace_home = "/home/${local.workspace_user}"
  workspace_uid  = 1000
  workspace_gid  = 1000

  workspace_images = {
    base = "ghcr.io/sourecode/coder-workspace:base"
    node = "ghcr.io/sourecode/coder-workspace:node"
    cpp  = "ghcr.io/sourecode/coder-workspace:cpp"
    php  = "ghcr.io/sourecode/coder-workspace:php"
    go     = "ghcr.io/sourecode/coder-workspace:go"
    go-php = "ghcr.io/sourecode/coder-workspace:go-php"
  }

  git_author_name            = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email           = data.coder_workspace_owner.me.email

  additional_ports = [
    for entry in jsondecode(data.coder_parameter.additional_ports.value) : {
      internal = tonumber(split(":", split("/", entry)[0])[0])
      external = tonumber(split(":", split("/", entry)[0])[1])
      protocol = length(split("/", entry)) > 1 ? split("/", entry)[1] : "tcp"
    }
  ]
}

data "coder_parameter" "workspace_image" {
  type         = "string"
  name         = "workspace_image"
  display_name = "Workspace image"
  description  = "Which stack image this workspace runs. Each option maps to a ghcr.io/sourecode/coder-workspace tag."
  default      = "base"
  mutable      = true

  option {
    name  = "base — dev-kit only (Node via nvm, Claude, rtk, web-shell, home-persist)"
    value = "base"
  }
  option {
    name  = "node — reserved for future Node-specific tooling (currently identical to base)"
    value = "node"
  }
  option {
    name  = "cpp — base + llvm + cmake + sccache"
    value = "cpp"
  }
  option {
    name  = "php — base + Sury PHP (default 8.5) + composer + symfony-cli + frankenphp + pvm"
    value = "php"
  }
  option {
    name  = "go — base + Go (latest stable)"
    value = "go"
  }
  option {
    name  = "go-php — base + Go (latest stable) + Sury PHP (default 8.5) + composer + symfony-cli + frankenphp + pvm"
    value = "go-php"
  }
}

data "coder_parameter" "repo_url" {
  type         = "string"
  name         = "repo_url"
  display_name = "Git Repository"
  description  = "Git repository to clone into the workspace home."
  default      = "https://github.com/coder/coder"
  mutable      = true
}

data "coder_parameter" "directory" {
  type         = "string"
  name         = "directory"
  display_name = "Working directory"
  description  = "Folder IDE modules and web-shell open by default."
  default      = "/home/coder/projects"
  mutable      = true
}

data "coder_parameter" "additional_ports" {
  type         = "list(string)"
  name         = "additional_ports"
  display_name = "Additional ports"
  description  = <<-EOT
    Extra container ports to publish to the host.

    Format per entry: `internal:external[/protocol]`
      - `internal`  — port inside the workspace container
      - `external`  — port on the host
      - `protocol`  — `tcp` or `udp` (optional, defaults to `tcp`)

    Examples:
      - `9000:9000/udp`  — SRT ingest on UDP 9000
      - `8080:18080`     — HTTP on host 18080 → container 8080 (tcp)
      - `5432:5432/tcp`  — Postgres

    Notes:
      - Changing this list replaces the container on next start.
      - Host port conflicts fail at apply time.
      - Malformed entries fail at plan time.
  EOT
  default      = jsonencode([])
  mutable      = true
}

data "coder_parameter" "home_persist_paths" {
  type         = "string"
  name         = "home_persist_paths"
  display_name = "Extra persisted HOME paths"
  description  = "Comma-separated $HOME-relative paths to persist beyond the defaults (e.g. '.gitconfig,.bash_history,.config/my-tool/'). Trailing / marks a directory."
  default      = ""
  mutable      = true
}

provider "coder" {}
provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = data.coder_parameter.directory.value

  # Workspace identity is exposed to shells and coder_script blocks so
  # home-persist-resolve can scope per-workspace paths under
  # /mnt/home-persist/.workspaces/$CODER_WORKSPACE_ID/. Name is informational
  # (renameable); ID is the stable key.
  env = {
    CODER_WORKSPACE_NAME = data.coder_workspace.me.name
    CODER_WORKSPACE_ID   = data.coder_workspace.me.id
  }

  startup_script = <<-EOT
    set -e

    # SSH key for git-over-SSH clones. Public key + allowed_signers come via
    # coder_script.git_ssh_signing below.
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo "${data.coder_workspace_owner.me.ssh_private_key}" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519

  EOT

  shutdown_script = ""

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script       = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

# IDE modules attach to the single workspace agent.
# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = data.coder_parameter.directory.value
  order    = 1
}

resource "coder_app" "web-shell" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "web-shell"
  display_name = "web-shell"
  url          = "http://localhost:4000"
  icon         = "/icon/terminal.svg"
  subdomain    = true
  share        = "owner"
  order        = 2

  healthcheck {
    url       = "http://localhost:4000/api/sessions"
    interval  = 5
    threshold = 6
  }
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = data.coder_parameter.directory.value
}

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.repo_url.value
  base_dir = "~/projects"
  version  = "~> 1.0"
}

# Git configuration: identity + SSH commit signing. Identity uses the Coder
# workspace owner. Signing uses the ed25519 key Coder provisions per owner —
# the user must also register this public key as a *signing key* on
# GitHub/GitLab (separate from auth keys) for commits to show as Verified.
resource "coder_script" "git_setup" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Git setup"
  icon         = "/icon/git.svg"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    printf '%s' "${base64encode(data.coder_workspace_owner.me.ssh_public_key)}" | base64 -d > ~/.ssh/id_ed25519.pub
    chmod 644 ~/.ssh/id_ed25519.pub

    printf '%s %s\n' \
      "${data.coder_workspace_owner.me.email}" \
      "$(cat ~/.ssh/id_ed25519.pub)" \
      > ~/.ssh/allowed_signers
    chmod 644 ~/.ssh/allowed_signers

    ssh-keyscan -t rsa,ecdsa,ed25519 github.com gitlab.com bitbucket.org \
      >> ~/.ssh/known_hosts 2>/dev/null || true
    sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts

    git config --global user.name  "${local.git_author_name}"
    git config --global user.email "${local.git_author_email}"
    git config --global gpg.format ssh
    git config --global user.signingkey ~/.ssh/id_ed25519.pub
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

    # Global gitignore. Git auto-picks $XDG_CONFIG_HOME/git/ignore as
    # core.excludesFile on Linux — no extra config needed. Keeps IDE-local
    # project state (JetBrains .idea/) out of every repo the user touches,
    # without needing per-repo .gitignore edits.
    mkdir -p ~/.config/git
    printf '.idea/\n.codex\n' > ~/.config/git/ignore
  EOT
}

# Lifecycle hooks baked into the image by the dev-kit install scripts.
# Sequential execution because rtk writes into ~/.claude, which must be
# symlinked into the persistence volume by home-persist first.
# start_blocks_login keeps IDEs / shells from connecting before $HOME is ready.
resource "coder_script" "lifecycle_init" {
  count              = data.coder_workspace.me.start_count
  agent_id           = coder_agent.main.id
  display_name       = "Workspace init"
  icon               = "/icon/docker.svg"
  run_on_start       = true
  start_blocks_login = true
  script             = <<-EOT
    set -e

    # Source ~/.profile so PATH hooks (e.g. $HOME/.local/bin from claude-code)
    # take effect for the post-create scripts invoked below.
    [ -f "$HOME/.profile" ] && . "$HOME/.profile"

    user_paths="${data.coder_parameter.home_persist_paths.value}"
    if [ -n "$user_paths" ]; then
      paths_json='[]'
      IFS=',' read -ra parts <<<"$user_paths"
      for p in "$${parts[@]}"; do
        p="$${p#"$${p%%[![:space:]]*}"}"
        p="$${p%"$${p##*[![:space:]]}"}"
        [ -z "$p" ] && continue
        paths_json=$(jq -c --arg p "$p" '. + [$p]' <<<"$paths_json")
      done
      if [ "$paths_json" != "[]" ]; then
        sudo mkdir -p /etc/home-persist.d
        jq -n --argjson paths "$paths_json" '{source:"user",paths:$paths}' \
          | sudo tee /etc/home-persist.d/user.json >/dev/null
      fi
    fi

    # One-shot migration sweeps. Each entry removes an owner-scoped path that
    # has since been moved to scope=workspace. Gated by a sentinel on the
    # shared volume so only the first workspace to cycle after the switch
    # pays the cost; subsequent workspaces see the sentinel and skip. Safe
    # to delete a migration block once every owner has cycled past it.
    migration_sweep() {
      sentinel="/mnt/home-persist/.workspaces/.migrated/$1"
      orphan="/mnt/home-persist/$2"
      [ -f "$sentinel" ] && return
      [ -e "$orphan" ] && rm -rf "$orphan"
      mkdir -p "$(dirname "$sentinel")"
      touch "$sentinel"
    }
    if [ -w /mnt/home-persist ]; then
      migration_sweep jetbrains-cache-owner-to-ephemeral .cache/JetBrains
      mkdir -p /mnt/home-persist/.jetbrains-dist
      rm -rf /mnt/home-persist/.local/share/JetBrains/Daemon
      rm -rf /mnt/home-persist/.local/share/JetBrains/Toolbox/download
      rm -rf /mnt/home-persist/.local/share/JetBrains/Toolbox/backup
      if [ -d /mnt/home-persist/.local/share/JetBrains ]; then
        find /mnt/home-persist/.local/share/JetBrains -mindepth 2 -maxdepth 2 -type d \
          \( -name caches -o -name logs \) -exec rm -rf {} +
      fi
    fi

    [ -x /usr/local/bin/home-persist-resolve ]          && /usr/local/bin/home-persist-resolve

    mkdir -p "$HOME/.local/share/JetBrains/Toolbox"
    printf '%s\n' \
      '{' \
      '  "tools": {' \
      '    "allowUpdate": false,' \
      '    "location": [' \
      '      {' \
      '        "path": "/mnt/home-persist/.jetbrains-dist",' \
      '        "levels": 1' \
      '      }' \
      '    ]' \
      '  }' \
      '}' \
      > "$HOME/.local/share/JetBrains/Toolbox/environment.json"

    mkdir -p "$HOME/.config/JetBrains" "$HOME/.local/share/JetBrains"
    if [ -d "$HOME/.local/share/JetBrains" ]; then
      for share_dir in "$HOME"/.local/share/JetBrains/*; do
        [ -d "$share_dir" ] || continue
        share_name="$(basename "$share_dir")"
        case "$share_name" in
          Toolbox|Daemon|consentOptions)
            continue
            ;;
        esac
        mkdir -p "$HOME/.config/JetBrains/$share_name"
      done
    fi
    if [ -d "$HOME/.config/JetBrains" ]; then
      for ide_dir in "$HOME"/.config/JetBrains/*; do
        [ -d "$ide_dir" ] || continue
        ide_name="$(basename "$ide_dir")"
        printf '%s\n' \
          "idea.config.path=$ide_dir" \
          "idea.plugins.path=$HOME/.local/share/JetBrains/$ide_name/plugins" \
          "idea.system.path=/tmp/jetbrains/system/$ide_name" \
          "idea.log.path=/tmp/jetbrains/log/$ide_name" \
          > "$ide_dir/idea.properties"
      done
    fi

    [ -x "$HOME/.local/share/rtk/post-create.sh" ]      && "$HOME/.local/share/rtk/post-create.sh"
    exit 0
  EOT
}

# Drop leftover state entries from pre-c56cc1d templates without deleting the
# underlying Docker volumes. Existing workspaces still carry
# docker_volume.shared / docker_volume.home_persist in their tfstate; on every
# stop/destroy Terraform tries to remove the real volumes (which hold shared
# and per-owner persistent data). These `removed` blocks tell Terraform to
# forget the addresses on the next apply while leaving the volumes intact.
# Safe to delete once no workspace has those addresses in state anymore.
removed {
  from = docker_volume.shared
  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_volume.home_persist
  lifecycle {
    destroy = false
  }
}

# Persistent storage for the workspace's inner dockerd. Without this, every
# `docker pull`, buildx cache, and image built inside the workspace is lost
# on every restart. The workspace's dockerd runs under sysbox-runc.
resource "docker_volume" "docker_data" {
  name = "coder-${data.coder_workspace.me.id}-docker"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# Per-workspace projects volume. Cloned repos + work-in-progress live here
# so they survive workspace restarts. $HOME itself is image-owned and resets
# each start; per-owner state that must persist outside projects goes through
# home-persist (see docs/persistence.md).
resource "docker_volume" "projects_volume" {
  name = "coder-${data.coder_workspace.me.id}-projects"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# Pin the workspace image to its current remote digest. Every plan re-reads
# the registry data source; when the remote `:tag` points at a new digest,
# docker_image.name changes (different `name@sha256:...`), forcing the
# resource to be replaced — which downloads the new image and advances
# image_id, which in turn replaces docker_container.workspace. Beats
# pull_triggers: the identity of the resource itself is the digest, so there
# is no way for the provider to "already have it" and skip.
data "docker_registry_image" "workspace" {
  name = local.workspace_images[data.coder_parameter.workspace_image.value]
}

resource "docker_image" "workspace" {
  name         = "${data.docker_registry_image.workspace.name}@${data.docker_registry_image.workspace.sha256_digest}"
  keep_locally = true
}

resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = docker_image.workspace.image_id
  runtime = "sysbox-runc"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  # Give systemd enough time to shut dockerd down cleanly on stop. The
  # default (10s) causes SIGKILL mid-flush, which corrupts the persistent
  # /var/lib/docker volume on the next start.
  stop_timeout = 120

  # PID 1 is /sbin/init (systemd). coder-agent.service (baked into the image)
  # execs /etc/coder/agent-init.sh, which this `upload` block provides.
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

  upload {
    file       = "/etc/coder/agent-init.sh"
    executable = true
    content    = replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  }

  # Config for web-shell.service (baked into the image). The unit reads this
  # via EnvironmentFile; changing the `directory` parameter re-renders it and
  # the unit picks it up on next start.
  upload {
    file    = "/etc/default/web-shell"
    content = <<-EOT
      WEB_SHELL_CWD=${data.coder_parameter.directory.value}
      WEB_SHELL_TITLE_PREFIX=${data.coder_workspace.me.name}
    EOT
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  dynamic "ports" {
    for_each = local.additional_ports
    content {
      internal = ports.value.internal
      external = ports.value.external
      protocol = ports.value.protocol
    }
  }

  volumes {
    container_path = "${local.workspace_home}/projects"
    volume_name    = docker_volume.projects_volume.name
    read_only      = false
  }

  # home_persist and shared are NOT terraform-managed — they're owned outside
  # this workspace's lifecycle (per-owner and deployment-wide respectively).
  # Referencing them by name means workspace destroy won't try to remove them
  # (which would fail while other workspaces hold them). Docker auto-creates
  # on first attach; pre-create on the host if you want labels for tracking.
  volumes {
    container_path = "/mnt/home-persist"
    volume_name    = "coder-${data.coder_workspace_owner.me.name}-home-persist"
    read_only      = false
  }

  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_data.name
    read_only      = false
  }

  volumes {
    container_path = "/mnt/shared"
    volume_name    = "coder-shared"
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
