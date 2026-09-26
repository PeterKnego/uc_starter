# HCLOUD_TOKEN comes from the environment (cloud-infra/.env).
locals {
  network_zone = (
    contains(["ash"], var.region) ? "us-east" :
    contains(["hil"], var.region) ? "us-west" :
    contains(["sin"], var.region) ? "ap-southeast" :
    "eu-central"
  )
}

resource "hcloud_ssh_key" "this" {
  name       = "${var.owner}-key"
  public_key = var.ssh_public_key
  labels     = var.labels
}

resource "hcloud_network" "this" {
  name     = "${var.owner}-net"
  ip_range = "10.10.0.0/16"
  labels   = var.labels
}

resource "hcloud_network_subnet" "this" {
  network_id   = hcloud_network.this.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = "10.10.1.0/24"
}

# The public IPs exist before the servers, so the firewall can name them and
# every server boots with the firewall already applied (no unfiltered window).
resource "hcloud_primary_ip" "node" {
  count       = 3
  name        = "${var.owner}-ip${count.index}"
  type        = "ipv4"
  location    = var.region
  auto_delete = false
  labels      = var.labels
}

# Hetzner firewalls filter the public interface only; the private network is
# not filtered, so node UDP and metrics stay reachable between the hosts. The
# gateway rule admits the hosts' own public IPs (the test/bench client runs on
# a host and is redirected to public members).
resource "hcloud_firewall" "this" {
  name   = "${var.owner}-fw"
  labels = var.labels

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.allow_ssh_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "${min(var.gateway_ports...)}-${max(var.gateway_ports...)}"
    source_ips = concat([var.client_cidr], [for ip in hcloud_primary_ip.node : "${ip.ip_address}/32"])
  }
}

resource "hcloud_server" "node" {
  count        = 3
  name         = "${var.owner}-node${count.index}"
  server_type  = var.instance_type
  image        = "ubuntu-24.04"
  location     = var.region
  ssh_keys     = [hcloud_ssh_key.this.id]
  firewall_ids = [hcloud_firewall.this.id]
  labels       = merge(var.labels, { role = "node${count.index}" })

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.node[count.index].id
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.this.id
    ip         = "10.10.1.${count.index + 10}"
  }

  depends_on = [hcloud_network_subnet.this]
}
