locals {
  enable_hetzner = var.cloud == "hetzner"
  enable_aws     = var.cloud == "aws"
  enable_gcp     = var.cloud == "gcp"

  default_types = {
    hetzner = { x86_64 = "cpx21", aarch64 = "cax11" }
    aws     = { x86_64 = "c7i.large", aarch64 = "c7g.large" }
    gcp     = { x86_64 = "e2-standard-2", aarch64 = "t2a-standard-2" }
  }
  default_regions = { hetzner = "nbg1", aws = "us-east-1", gcp = "us-central1" }

  instance_type = var.instance_type != "" ? var.instance_type : local.default_types[var.cloud][var.arch]
  region        = var.region != "" ? var.region : local.default_regions[var.cloud]

  # The CPU an instance type runs, per cloud's naming: Hetzner CAX, AWS
  # Graviton (a "g" after the generation digit: c7g, m7gd, t4g), GCP Tau
  # T2A / Axion C4A / N4A.
  type_arch = (
    local.enable_hetzner ? (can(regex("^cax", local.instance_type)) ? "aarch64" : "x86_64") :
    local.enable_aws ? (can(regex("^[a-z]+[0-9]+g[a-z]*\\.", local.instance_type)) ? "aarch64" : "x86_64") :
    (can(regex("^(t2a|c4a|n4a)-", local.instance_type)) ? "aarch64" : "x86_64")
  )

  client_cidr   = var.allow_client_cidr != "" ? var.allow_client_cidr : var.allow_ssh_cidr
  gateway_ports = [for i in range(3) : var.base_port + 100 + i]
  labels        = { owner = var.owner, app = var.app_name, ttl_hours = tostring(var.ttl_hours) }
}

# Refusals before anything is created (terraform plan fails on them).
resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = local.type_arch == var.arch
      error_message = "instance_type ${local.instance_type} is ${local.type_arch}, but arch = \"${var.arch}\" (the bundle is built for arch). Set arch = \"${local.type_arch}\", or pick a ${var.arch} instance type."
    }
    precondition {
      condition     = var.allow_open_cidr || (var.allow_ssh_cidr != "0.0.0.0/0" && local.client_cidr != "0.0.0.0/0")
      error_message = "0.0.0.0/0 opens SSH or the gateways to the whole internet. Use your own IP/32 (curl -s https://checkip.amazonaws.com), or set allow_open_cidr = true if you mean it."
    }
  }
}

# Terraform configures every declared provider, even with count = 0 modules:
# the inactive ones get throwaway credentials and skip their probes.
provider "hcloud" {
  token = local.enable_hetzner ? null : "unusedunusedunusedunusedunusedunusedunusedunusedunusedunused1234"
}

provider "aws" {
  region                      = local.enable_aws ? local.region : "us-east-1"
  access_key                  = local.enable_aws ? null : "unused-dummy"
  secret_key                  = local.enable_aws ? null : "unused-dummy"
  skip_credentials_validation = !local.enable_aws
  skip_requesting_account_id  = !local.enable_aws
  skip_metadata_api_check     = !local.enable_aws
}

provider "google" {
  region       = local.enable_gcp ? local.region : "us-central1"
  access_token = local.enable_gcp ? null : "unused-dummy-token"
}

module "hetzner" {
  source     = "./modules/hetzner"
  count      = local.enable_hetzner ? 1 : 0
  depends_on = [terraform_data.guards]

  owner          = var.owner
  instance_type  = local.instance_type
  region         = local.region
  ssh_public_key = var.ssh_public_key
  allow_ssh_cidr = var.allow_ssh_cidr
  client_cidr    = local.client_cidr
  gateway_ports  = local.gateway_ports
  labels         = local.labels
}

module "aws" {
  source     = "./modules/aws"
  count      = local.enable_aws ? 1 : 0
  depends_on = [terraform_data.guards]

  owner          = var.owner
  instance_type  = local.instance_type
  arch           = var.arch
  region         = local.region
  ssh_public_key = var.ssh_public_key
  allow_ssh_cidr = var.allow_ssh_cidr
  client_cidr    = local.client_cidr
  gateway_ports  = local.gateway_ports
  labels         = local.labels
}

module "gcp" {
  source     = "./modules/gcp"
  count      = local.enable_gcp ? 1 : 0
  depends_on = [terraform_data.guards]

  owner          = var.owner
  instance_type  = local.instance_type
  arch           = var.arch
  region         = local.region
  ssh_public_key = var.ssh_public_key
  allow_ssh_cidr = var.allow_ssh_cidr
  client_cidr    = local.client_cidr
  gateway_ports  = local.gateway_ports
  labels         = local.labels
}

locals {
  active = (
    local.enable_hetzner ? module.hetzner[0] :
    local.enable_aws ? module.aws[0] :
    module.gcp[0]
  )
}
