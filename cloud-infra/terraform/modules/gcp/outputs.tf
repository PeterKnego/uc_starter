output "nodes" {
  value = [for i, s in google_compute_instance.node : {
    name       = s.name
    role       = "node${i}"
    public_ip  = google_compute_address.public[i].address
    private_ip = "10.10.1.${i + 10}"
  }]
}
output "ssh_user" { value = "ubuntu" }
