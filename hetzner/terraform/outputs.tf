output "ipv4" {
  value = hcloud_primary_ip.v4.ip_address
}

output "ipv6" {
  value = one(hcloud_server.node[*].ipv6_address)
}
