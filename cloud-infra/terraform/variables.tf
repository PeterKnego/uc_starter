variable "cloud" {
  description = "hetzner | aws | gcp"
  type        = string
  default     = "hetzner"
  validation {
    condition     = contains(["hetzner", "aws", "gcp"], var.cloud)
    error_message = "cloud must be one of: hetzner, aws, gcp."
  }
}

variable "arch" {
  description = "The hosts' CPU; the bundle is built for it (make package ARCH=)."
  type        = string
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "aarch64"], var.arch)
    error_message = "arch must be x86_64 or aarch64."
  }
}

variable "instance_type" {
  description = "Empty: the cloud's small default for arch."
  type        = string
  default     = ""
}

variable "region" {
  description = "Empty: nbg1 (hetzner), us-east-1 (aws), us-central1 (gcp)."
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key contents installed on the hosts."
  type        = string
}

variable "ssh_private_key_file" {
  description = "The matching private key; read by the scripts, not by Terraform."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "allow_ssh_cidr" {
  description = "Who may SSH to the hosts (your IP/32)."
  type        = string
}

variable "allow_client_cidr" {
  description = "Who may reach the gateways. Empty: allow_ssh_cidr."
  type        = string
  default     = ""
}

variable "allow_open_cidr" {
  description = "Set true to accept 0.0.0.0/0 in allow_ssh_cidr / allow_client_cidr."
  type        = bool
  default     = false
}

variable "ttl_hours" {
  description = "Advisory: make cloud-status warns past it."
  type        = number
  default     = 4
}

variable "owner" {
  description = "Prefix for every resource name (the Makefile sets <app>-<user>)."
  type        = string
}

variable "app_name" {
  description = "From uc-app.env (the Makefile sets it)."
  type        = string
}

variable "base_port" {
  description = "From uc-app.env (the Makefile sets it)."
  type        = number
}
