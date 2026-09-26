output "nodes" {
  description = "[node0, node1, node2]: name, role, public_ip, private_ip."
  value       = local.active.nodes
}
output "ssh_user" { value = local.active.ssh_user }
output "arch" { value = var.arch }
output "instance_type" { value = local.instance_type }
output "region" { value = local.region }
output "cloud" { value = var.cloud }
output "ttl_hours" { value = var.ttl_hours }
