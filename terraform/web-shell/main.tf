terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "port" {
  type        = number
  description = "The port to run web-shell on."
  default     = 4000
}

variable "host" {
  type        = string
  description = "The bind address web-shell should listen on."
  default     = "127.0.0.1"
}

variable "auth_token" {
  type        = string
  description = "Optional shared bearer token enforced by web-shell. Leave empty when fronted by Coder."
  default     = ""
  sensitive   = true
}

variable "install_version" {
  type        = string
  description = "Release tag of web-shell to install (e.g. 'v0.1.0'). Empty means latest."
  default     = ""
}

variable "log_path" {
  type        = string
  description = "The path to log web-shell to."
  default     = "/tmp/web-shell.log"
}

variable "display_name" {
  type        = string
  description = "The display name for the web-shell application."
  default     = "web-shell"
}

variable "slug" {
  type        = string
  description = "The slug for the web-shell application."
  default     = "web-shell"
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Serve web-shell on its own subdomain. Required for the WebSocket /ws endpoint
    to work reliably behind path-based proxying.
  EOT
  default     = true
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "open_in" {
  type        = string
  description = <<-EOT
    Determines where the app will be opened. Valid values are `"tab"` and `"slim-window" (default)`.
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
  EOT
  default     = "slim-window"
  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

resource "coder_script" "web-shell" {
  agent_id     = var.agent_id
  display_name = "web-shell"
  icon         = "/icon/terminal.svg"
  script = templatefile("${path.module}/run.sh", {
    VERSION : var.install_version,
    HOST : var.host,
    PORT : var.port,
    AUTH_TOKEN : var.auth_token,
    LOG_PATH : var.log_path,
  })
  run_on_start = true
}

resource "coder_app" "web-shell" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}"
  icon         = "/icon/terminal.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.port}/api/sessions"
    interval  = 5
    threshold = 6
  }
}
