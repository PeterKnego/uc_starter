mock_provider "hcloud" {}
mock_provider "aws" {}
mock_provider "google" {}

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
