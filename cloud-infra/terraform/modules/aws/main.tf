locals {
  ami_arch = var.arch == "aarch64" ? "arm64" : "amd64"
  tags     = merge(var.labels, { Name = var.owner })
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${local.ami_arch}-server-*"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags                 = local.tags
}

resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags                    = local.tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = local.tags
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

resource "aws_security_group" "this" {
  name   = "${var.owner}-sg"
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.allow_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "private" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "10.10.1.0/24"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "gateways_clients" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.client_cidr
  ip_protocol       = "tcp"
  from_port         = min(var.gateway_ports...)
  to_port           = max(var.gateway_ports...)
}

# The hosts' own public IPs: the test/bench client runs on a host and is
# redirected to public members (separate rules: no cycle with the instances).
resource "aws_vpc_security_group_ingress_rule" "gateways_hosts" {
  count             = 3
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "${aws_instance.node[count.index].public_ip}/32"
  ip_protocol       = "tcp"
  from_port         = min(var.gateway_ports...)
  to_port           = max(var.gateway_ports...)
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_key_pair" "this" {
  key_name   = "${var.owner}-key"
  public_key = var.ssh_public_key
  tags       = local.tags
}

resource "aws_instance" "node" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.this.id
  vpc_security_group_ids = [aws_security_group.this.id]
  key_name               = aws_key_pair.this.key_name
  private_ip             = "10.10.1.${count.index + 10}"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(local.tags, { Name = "${var.owner}-node${count.index}", role = "node${count.index}" })
}
