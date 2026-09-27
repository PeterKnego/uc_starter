# Copy to cloud-infra/terraform.tfvars (gitignored) and edit.
cloud         = "hetzner" # hetzner | aws | gcp
arch          = "x86_64"  # x86_64 | aarch64 — the hosts' CPU; the bundle is built for it
region        = ""        # empty: nbg1 | us-east-1 | us-central1
instance_type = ""        # empty: cpx21/cax11 | c7i.large/c7g.large | e2-standard-2/t2a-standard-2

ssh_public_key       = "ssh-ed25519 AAAA... you@laptop" # contents of ~/.ssh/id_ed25519.pub
ssh_private_key_file = "~/.ssh/id_ed25519"

allow_ssh_cidr    = "203.0.113.7/32" # your IP: curl -s https://checkip.amazonaws.com
allow_client_cidr = ""               # empty: same as allow_ssh_cidr

ttl_hours = 4 # make cloud-status warns past this; the hosts bill until make cloud-destroy
