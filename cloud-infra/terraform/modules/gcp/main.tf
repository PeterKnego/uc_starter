# GOOGLE_PROJECT and GOOGLE_APPLICATION_CREDENTIALS come from the environment.
data "google_compute_zones" "up" {
  region = var.region
  status = "UP"
}

locals {
  # Not every region has an "-a" zone (us-east1, europe-west1); try() keeps
  # plans working where the data source has no names yet (mock providers).
  zone  = try(sort(data.google_compute_zones.up.names)[0], "${var.region}-a")
  image = var.arch == "aarch64" ? "ubuntu-os-cloud/ubuntu-2404-lts-arm64" : "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

resource "google_compute_network" "this" {
  name                    = "${var.owner}-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = "${var.owner}-subnet"
  ip_cidr_range = "10.10.1.0/24"
  region        = var.region
  network       = google_compute_network.this.id
}

resource "google_compute_address" "public" {
  count  = 3
  name   = "${var.owner}-ip${count.index}"
  region = var.region
}

resource "google_compute_firewall" "ssh" {
  name          = "${var.owner}-ssh"
  network       = google_compute_network.this.name
  source_ranges = [var.allow_ssh_cidr]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "private" {
  name          = "${var.owner}-private"
  network       = google_compute_network.this.name
  source_ranges = ["10.10.1.0/24"]
  allow { protocol = "all" }
}

resource "google_compute_firewall" "gateways" {
  name          = "${var.owner}-gateways"
  network       = google_compute_network.this.name
  source_ranges = concat([var.client_cidr], [for a in google_compute_address.public : "${a.address}/32"])
  allow {
    protocol = "tcp"
    ports    = ["${min(var.gateway_ports...)}-${max(var.gateway_ports...)}"]
  }
}

resource "google_compute_instance" "node" {
  count        = 3
  name         = "${var.owner}-node${count.index}"
  machine_type = var.instance_type
  zone         = local.zone
  labels       = merge(var.labels, { role = "node${count.index}" })

  boot_disk {
    initialize_params {
      image = local.image
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id
    network_ip = "10.10.1.${count.index + 10}"
    access_config {
      nat_ip = google_compute_address.public[count.index].address
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
}
