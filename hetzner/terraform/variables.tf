# All of these are set by ../lab.sh from ../lab.env (TF_VAR_*).

variable "hcloud_token" {
  description = "Hetzner Cloud API token (read/write) for the project the lab lives in."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Public key for the lab login user."
  type        = string
}

variable "admin_cidrs" {
  description = "Who may reach SSH. lab.sh passes the Mac's current public address."
  type        = list(string)
}

variable "node_fqdn" {
  description = "The controlrepo node this server impersonates; hiera classifies by it."
  type        = string
  default     = "matrix01.voxpupu.li"
}

variable "location" {
  description = "Hetzner location: nbg1, fsn1 or hel1."
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  description = "x86 type. cx33 is 4 vCPU / 8 GB; the stack idles near 2 GB."
  type        = string
  default     = "cx33"
}

variable "server_enabled" {
  description = "False keeps the address, firewall and key but no server (lab.sh down)."
  type        = bool
  default     = true
}
