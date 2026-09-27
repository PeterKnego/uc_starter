variable "owner" { type = string }
variable "instance_type" { type = string }
variable "region" { type = string }
variable "ssh_public_key" { type = string }
variable "allow_ssh_cidr" { type = string }
variable "client_cidr" { type = string }
variable "gateway_ports" { type = list(number) }
variable "labels" { type = map(string) }
