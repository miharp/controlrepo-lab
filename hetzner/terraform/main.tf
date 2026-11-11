# One disposable x86 server that runs a voxpupuli/controlrepo node role
# with real DNS names, real ACME and real federation. Unlike the
# Tailscale-only OpenVox lab, 80 and 443 are open to the world: Let's
# Encrypt and other homeservers have to reach it.

locals {
  short = split(".", var.node_fqdn)[0]
}

resource "hcloud_ssh_key" "lab" {
  name       = "controlrepo-lab"
  public_key = var.ssh_public_key
}

# Kept across `lab.sh down` so the DNS records made by hand stay valid.
resource "hcloud_primary_ip" "v4" {
  name        = "controlrepo-lab-v4"
  type        = "ipv4"
  auto_delete = false
  location    = var.location
}

resource "hcloud_firewall" "lab" {
  name = "controlrepo-lab"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "node" {
  count = var.server_enabled ? 1 : 0

  name         = local.short
  image        = "ubuntu-24.04"
  server_type  = var.server_type
  location     = var.location
  firewall_ids = [hcloud_firewall.lab.id]
  # Without a key Hetzner mails a root password. profiles::base purges
  # this key from root on the first apply; the lab user is the way in.
  ssh_keys = [hcloud_ssh_key.lab.id]

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.v4.id
    ipv6_enabled = true
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    fqdn           = var.node_fqdn
    short          = local.short
    ssh_public_key = var.ssh_public_key
  })

  # A new key or cloud-init edit should not replace a server mid-session.
  lifecycle {
    ignore_changes = [user_data, ssh_keys]
  }
}
