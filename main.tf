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

variable "workspace_image" {
  type        = string
  description = "Workspace container image. Must ship systemd as PID 1 + dockerd, and user `coder` at UID 1000 in the docker group. Built from Dockerfile.workspace in this repo and run under the sysbox-runc runtime."
  default     = "sourecode/coder-workspace:latest"
}

variable "devcontainer_user" {
  type        = string
  description = "Linux user inside the built devcontainer (inner). Defined by the devcontainer's Dockerfile via build.args.USERNAME."
  default     = "dev"
}

variable "devcontainer_user_uid" {
  type        = number
  description = "UID for the devcontainer user."
  default     = 1000
}

variable "devcontainer_user_gid" {
  type        = number
  description = "GID for the devcontainer user."
  default     = 1000
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

locals {
  # Outer workspace user. Fixed because workspace_image ships with it baked in.
  workspace_user = "coder"
  workspace_home = "/home/${local.workspace_user}"
}

data "coder_parameter" "repo_url" {
  type         = "string"
  name         = "repo_url"
  display_name = "Git Repository"
  description  = "Enter the URL of the Git repository to clone into your workspace. This repository should contain a devcontainer.json file to configure your development environment."
  default      = "https://github.com/coder/coder"
  mutable      = true
}

data "coder_parameter" "directory" {
  type         = "string"
  name         = "directory"
  display_name = "Working directory"
  description  = "Path inside the workspace that IDE modules open by default."
  default      = "/workspaces"
  mutable      = true
}

# Ephemeral: resets to false after each build. Set to true to force the
# devcontainer to rebuild without using any cached layers on the next start.
data "coder_parameter" "rebuild_no_cache" {
  type         = "bool"
  name         = "rebuild_no_cache"
  display_name = "Rebuild devcontainer without cache"
  description  = "Drop the cached devcontainer image and BuildKit cache before the next build. One-shot."
  default      = "false"
  mutable      = true
  ephemeral    = true
  order        = 100
}

provider "coder" {}
provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch            = data.coder_provisioner.me.arch
  os              = "linux"
  startup_script  = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # SSH key + known_hosts so git over SSH works from inside the workspace.
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo "${data.coder_workspace_owner.me.ssh_private_key}" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    ssh-keyscan -t ed25519,rsa,ecdsa github.com gitlab.com >> ~/.ssh/known_hosts 2>/dev/null
    sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts

    # /mnt/devhome is the per-owner devcontainer home volume (see docker_volume.devhome).
    # devcontainer.json bind-mounts it into the inner container at /home/$DEVCONTAINER_USERNAME,
    # so every workspace for this owner shares one persistent home. Chown once per start
    # so the inner user (UID $DEVCONTAINER_USER_UID) can write it. mkdir is redundant when
    # docker already mounted the volume but keeps this idempotent if the mount path moves.
    sudo mkdir -p /mnt/devhome
    sudo chown "$DEVCONTAINER_USER_UID:$DEVCONTAINER_USER_GID" /mnt/devhome
  EOT
  shutdown_script = ""
  dir            = data.coder_parameter.directory.value

  # Exposed to the @devcontainers/cli process so devcontainer.json can resolve
  # them via ${localEnv:*} — see README for the per-user shared home pattern.
  # Git identity is set on the sub-agent instead (see coder_env.git_* below).
  env = {
    OWNER_USERNAME        = data.coder_workspace_owner.me.name
    DEVCONTAINER_USERNAME = var.devcontainer_user
    DEVCONTAINER_USER_UID = var.devcontainer_user_uid
    DEVCONTAINER_USER_GID = var.devcontainer_user_gid
  }

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
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
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

# @devcontainers/cli is pre-installed in the workspace image (Dockerfile.workspace).
# The coder/devcontainers-cli module is intentionally omitted because its
# runtime `npm install -g` step fails for the non-root `coder` user.

# code-server and JetBrains attach to the devcontainer's sub-agent (not the
# outer workspace agent), so IDEs run INSIDE the devcontainer — with its user,
# its language servers, its installed Features. Requires CODER_AGENT_DEVCONTAINERS_ENABLE
# (default true since v2.24) and a running coder_devcontainer resource.
#
# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_devcontainer.repo[0].subagent_id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_devcontainer.repo[0].subagent_id
  agent_name = "main"
  folder     = data.coder_parameter.directory.value
}

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.repo_url.value
  base_dir = "~"
  # This ensures that the latest non-breaking version of the module gets
  # downloaded, you can also pin the module version to prevent breaking
  # changes in production.
  version = "~> 1.0"
}

# Runs before the devcontainer CLI. When rebuild_no_cache is set, drop the
# prior devcontainer image and the BuildKit cache so the next build is from
# scratch. Script runs on the outer agent where dockerd lives.
resource "coder_script" "rebuild_no_cache" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "Devcontainer cache reset"
  icon         = "/icon/docker.svg"
  run_on_start = true
  start_blocks_login = false
  script       = <<-EOT
    set -e
    if [ "${data.coder_parameter.rebuild_no_cache.value}" != "true" ]; then
      exit 0
    fi
    echo "rebuild_no_cache=true — dropping devcontainer images and build cache"
    imgs=$(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^vsc-' || true)
    if [ -n "$imgs" ]; then
      echo "$imgs" | xargs -r docker image rm -f || true
    fi
    docker buildx prune -af || true
  EOT
}

# Automatically start the devcontainer for the workspace.
resource "coder_devcontainer" "repo" {
  count            = data.coder_workspace.me.start_count
  agent_id         = coder_agent.main.id
  workspace_folder = "~/${module.git-clone[0].folder_name}"
}

# Git identity inside the devcontainer. coder_env on the sub-agent injects
# these into the shell environment of the devcontainer's user.
resource "coder_env" "git_author_name" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_devcontainer.repo[0].subagent_id
  name     = "GIT_AUTHOR_NAME"
  value    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_author_email" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_devcontainer.repo[0].subagent_id
  name     = "GIT_AUTHOR_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

resource "coder_env" "git_committer_name" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_devcontainer.repo[0].subagent_id
  name     = "GIT_COMMITTER_NAME"
  value    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_committer_email" {
  count    = data.coder_workspace.me.start_count
  agent_id = coder_devcontainer.repo[0].subagent_id
  name     = "GIT_COMMITTER_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

# SSH commit signing inside the devcontainer. Uses the ed25519 key Coder
# provisions per workspace owner. The user must also register this public key
# as a *signing key* on GitHub/GitLab (separate from auth keys) for commits
# to show as Verified on the web UI.
resource "coder_script" "git_ssh_signing" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_devcontainer.repo[0].subagent_id
  display_name = "Git SSH signing setup"
  icon         = "/icon/git.svg"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Coder-provisioned ed25519 key (same one the outer workspace uses for git clones).
    printf '%s' "${base64encode(data.coder_workspace_owner.me.ssh_private_key)}" | base64 -d > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    printf '%s' "${base64encode(data.coder_workspace_owner.me.ssh_public_key)}"  | base64 -d > ~/.ssh/id_ed25519.pub
    chmod 644 ~/.ssh/id_ed25519.pub

    # allowed_signers lets `git log --show-signature` / `git verify-commit`
    # validate your own commits locally.
    printf '%s %s\n' \
      "${data.coder_workspace_owner.me.email}" \
      "$(cat ~/.ssh/id_ed25519.pub)" \
      > ~/.ssh/allowed_signers
    chmod 644 ~/.ssh/allowed_signers

    # known_hosts for common forges so git over SSH doesn't race / prompt.
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com gitlab.com bitbucket.org \
      >> ~/.ssh/known_hosts 2>/dev/null || true
    sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts

    # Global git config: sign every commit + tag with SSH.
    git config --global gpg.format ssh
    git config --global user.signingkey ~/.ssh/id_ed25519.pub
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
  EOT
}

# Persistent storage for the workspace's inner dockerd (/var/lib/docker).
# Without this, every devcontainer image + its layer cache is lost on every
# workspace restart, so feature installs run from scratch. With this, BuildKit
# reuses cached layers on rebuilds, and previously-pulled/built devcontainer
# images are instantly available again.
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

# Per-owner devcontainer home. Lives at the HOST level (outer dockerd), not inside
# any workspace's inner dockerd, so every workspace this owner starts sees the same
# home contents — shell history, git config, ~/.claude credentials, tool caches,
# everything. Survives workspace deletion and `rebuild_no_cache` (which only touches
# inner dockerd state). Bind-mounted into the devcontainer via devcontainer.json:
#   "mounts": ["source=/mnt/devhome,target=/home/${DEVCONTAINER_USERNAME},type=bind"]
# First-ever attach is empty: rely on an onCreateCommand in devcontainer.json to
# seed from /etc/skel when $HOME has no entries.
resource "docker_volume" "devhome" {
  name = "coder-${data.coder_workspace_owner.me.name}-devhome"
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

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
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
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = var.workspace_image
  runtime = "sysbox-runc"

  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name

  # Give systemd inside the workspace enough time to shut dockerd down cleanly
  # on stop. The default (10s) causes SIGKILL mid-flush, which corrupts the
  # persistent /var/lib/docker volume (missing RW layers, orphan BuildKit
  # snapshots) on the next start.
  stop_timeout = 120

  # PID 1 is /sbin/init (systemd). The Coder agent runs as a systemd unit
  # (coder-agent.service, baked into the image) that execs /etc/coder/agent-init.sh.
  # The init script is uploaded below with the workspace-specific token baked in.
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

  # Workspace home volume persists user data across workspace restarts.
  volumes {
    container_path = local.workspace_home
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Per-owner devcontainer home. Bind-mounted through into the inner devcontainer
  # via devcontainer.json so it follows the owner across every workspace they open.
  volumes {
    container_path = "/mnt/devhome"
    volume_name    = docker_volume.devhome.name
    read_only      = false
  }

  # Persist the inner dockerd's image / layer store so devcontainer builds
  # reuse the BuildKit cache across workspace restarts.
  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_data.name
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
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