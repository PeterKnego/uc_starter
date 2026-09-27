output "nodes" {
  value = [for i, s in hcloud_server.node : {
    name       = s.name
    role       = "node${i}"
    public_ip  = hcloud_primary_ip.node[i].ip_address
    private_ip = "10.10.1.${i + 10}"
  }]
}
output "ssh_user" { value = "root" }
