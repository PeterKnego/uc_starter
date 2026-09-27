# Mock values only where the modules need a well-formed one (numeric Hetzner
# ids, addresses that go into firewall CIDRs); the output-shape runs apply.
mock_provider "hcloud" {
  mock_resource "hcloud_network" {
    defaults = { id = "1" }
  }
  mock_resource "hcloud_firewall" {
    defaults = { id = "2" }
  }
  mock_resource "hcloud_ssh_key" {
    defaults = { id = "3" }
  }
  mock_resource "hcloud_primary_ip" {
    defaults = { id = "4", ip_address = "192.0.2.10" }
  }
}
mock_provider "aws" {
  mock_resource "aws_instance" {
    defaults = { public_ip = "192.0.2.20" }
  }
}
mock_provider "google" {
  mock_resource "google_compute_address" {
    defaults = { address = "192.0.2.30" }
  }
}

variables {
  ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@example"
  ssh_private_key_file = "~/.ssh/id_ed25519"
  allow_ssh_cidr       = "203.0.113.7/32"
  app_name             = "demo-app"
  base_port            = 7000
  owner                = "demo-app-dev"
}

run "hetzner_x86_defaults" {
  command = plan
  assert {
    condition     = output.instance_type == "cpx21" && output.arch == "x86_64"
    error_message = "hetzner x86_64 default type"
  }
}

run "hetzner_arm_defaults" {
  command = plan
  variables { arch = "aarch64" }
  assert {
    condition     = output.instance_type == "cax11"
    error_message = "hetzner aarch64 default type"
  }
}

run "aws_arm_defaults" {
  command = plan
  variables {
    cloud = "aws"
    arch  = "aarch64"
  }
  assert {
    condition     = output.instance_type == "c7g.large"
    error_message = "aws aarch64 default type"
  }
}

run "gcp_x86_defaults" {
  command = plan
  variables { cloud = "gcp" }
  assert {
    condition     = output.instance_type == "e2-standard-2"
    error_message = "gcp x86_64 default type"
  }
}

run "arch_mismatch_refused" {
  command = plan
  variables {
    arch          = "aarch64"
    instance_type = "cpx21"
  }
  expect_failures = [terraform_data.guards]
}

run "aws_graviton_type_is_arm" {
  command = plan
  variables {
    cloud         = "aws"
    instance_type = "m7g.large"
  }
  expect_failures = [terraform_data.guards]
}

run "open_client_cidr_refused" {
  command = plan
  variables { allow_client_cidr = "0.0.0.0/0" }
  expect_failures = [terraform_data.guards]
}

run "open_ssh_cidr_refused" {
  command = plan
  variables { allow_ssh_cidr = "0.0.0.0/0" }
  expect_failures = [terraform_data.guards]
}

run "open_cidr_allowed_when_explicit" {
  command = plan
  variables {
    allow_client_cidr = "0.0.0.0/0"
    allow_open_cidr   = true
  }
}

run "aws_x86_defaults" {
  command = plan
  variables { cloud = "aws" }
  assert {
    condition     = output.instance_type == "c7i.large"
    error_message = "aws x86_64 default type"
  }
}

run "gcp_arm_defaults" {
  command = plan
  variables {
    cloud = "gcp"
    arch  = "aarch64"
  }
  assert {
    condition     = output.instance_type == "t2a-standard-2"
    error_message = "gcp aarch64 default type"
  }
}

run "gcp_arch_mismatch_refused" {
  command = plan
  variables {
    cloud         = "gcp"
    arch          = "aarch64"
    instance_type = "e2-standard-2"
  }
  expect_failures = [terraform_data.guards]
}

# Output shape: `nodes` is the contract inventory.sh reads (node0..2, each
# with name, role, public_ip, private_ip); applied against the mocks.
run "hetzner_output_shape" {
  command = apply
  assert {
    condition     = length(output.nodes) == 3 && alltrue([for i, n in output.nodes : n.role == "node${i}" && n.private_ip == "10.10.1.${i + 10}" && n.public_ip != "" && n.name != ""])
    error_message = "hetzner nodes output: three entries node0..2 with name, role, public_ip, private_ip 10.10.1.1x"
  }
  assert {
    condition     = output.ssh_user == "root" && local.gateway_ports == [7100, 7101, 7102]
    error_message = "hetzner ssh_user, or gateway ports not BASE_PORT+100+i"
  }
}

run "aws_output_shape" {
  command = apply
  variables { cloud = "aws" }
  assert {
    condition     = length(output.nodes) == 3 && alltrue([for i, n in output.nodes : n.role == "node${i}" && n.private_ip == "10.10.1.${i + 10}" && n.public_ip != "" && n.name != ""])
    error_message = "aws nodes output: three entries node0..2 with name, role, public_ip, private_ip 10.10.1.1x"
  }
  assert {
    condition     = output.ssh_user == "ubuntu"
    error_message = "aws ssh_user"
  }
}

run "gcp_output_shape" {
  command = apply
  variables { cloud = "gcp" }
  assert {
    condition     = length(output.nodes) == 3 && alltrue([for i, n in output.nodes : n.role == "node${i}" && n.private_ip == "10.10.1.${i + 10}" && n.public_ip != "" && n.name != ""])
    error_message = "gcp nodes output: three entries node0..2 with name, role, public_ip, private_ip 10.10.1.1x"
  }
  assert {
    condition     = output.ssh_user == "ubuntu"
    error_message = "gcp ssh_user"
  }
}
