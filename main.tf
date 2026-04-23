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
  }
}

data "coder_parameter" "workspace_image" {
  type         = "string"
  name         = "workspace_image"
  display_name = "Workspace image"
  description  = "Which stack image this workspace runs. Each option maps to a ghcr.io/sourecode/coder-workspace tag."
  default      = "base"
  mutable      = true

  option {
    name  = "base — dev-kit only (Node via nvm, Claude, rtk, context-mode, web-shell, home-persist)"
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
  description  = "Folder IDE modules open by default."
  default      = "/home/coder"
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

  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # SSH key for git-over-SSH clones. Public key + allowed_signers come via
    # coder_script.git_ssh_signing below.
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo "${data.coder_workspace_owner.me.ssh_private_key}" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519

    # Per-owner persistence volume. home-persist-resolve (run via
    # coder_script.lifecycle_init below) symlinks declared $HOME paths into it.
    sudo mkdir -p /mnt/home-persist
    sudo chown "${local.workspace_uid}:${local.workspace_gid}" /mnt/home-persist

    # Deployment-wide shared drop box. Sticky-bit 1777 (like /tmp) so anyone
    # can write but only the file's owner can delete.
    sudo mkdir -p /mnt/shared
    sudo chmod 1777 /mnt/shared
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
  base_dir = "~"
  version  = "~> 1.0"
}

# Git identity for commits made from inside the workspace.
resource "coder_env" "git_author_name" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_NAME"
  value    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_author_email" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

resource "coder_env" "git_committer_name" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_NAME"
  value    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_committer_email" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

# SSH commit signing. Uses the ed25519 key Coder provisions per workspace
# owner. The user must also register this public key as a *signing key* on
# GitHub/GitLab (separate from auth keys) for commits to show as Verified.
resource "coder_script" "git_ssh_signing" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Git SSH signing setup"
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

    git config --global gpg.format ssh
    git config --global user.signingkey ~/.ssh/id_ed25519.pub
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
  EOT
}

# Lifecycle hooks baked into the image by the dev-kit install scripts.
# Sequential execution because context-mode and rtk write into ~/.claude,
# which must be symlinked into the persistence volume by home-persist first.
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

    [ -x /usr/local/bin/home-persist-resolve ]          && /usr/local/bin/home-persist-resolve
    [ -x /usr/local/share/context-mode/post-create.sh ] && /usr/local/share/context-mode/post-create.sh
    [ -x /usr/local/share/rtk/post-create.sh ]          && /usr/local/share/rtk/post-create.sh
    exit 0
  EOT
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

# Per-owner persistence volume. Follows the owner across every workspace they
# open. Survives workspace deletion. Bind-mounted at /mnt/home-persist; the
# home-persist resolver symlinks declared $HOME paths into it.
resource "docker_volume" "home_persist" {
  name = "coder-${data.coder_workspace_owner.me.name}-home-persist"
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
}

# Deployment-wide shared drop box. A single docker volume — fixed name, no
# per-owner/per-workspace suffix — attached to every workspace.
resource "docker_volume" "shared" {
  name = "coder-shared"
  lifecycle {
    ignore_changes = all
  }
}

# Per-workspace $HOME volume. Persists user data (~/.bashrc tweaks, cloned
# repo, build artefacts) across workspace restarts.
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
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

resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = local.workspace_images[data.coder_parameter.workspace_image.value]
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

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = local.workspace_home
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  volumes {
    container_path = "/mnt/home-persist"
    volume_name    = docker_volume.home_persist.name
    read_only      = false
  }

  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_data.name
    read_only      = false
  }

  volumes {
    container_path = "/mnt/shared"
    volume_name    = docker_volume.shared.name
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
