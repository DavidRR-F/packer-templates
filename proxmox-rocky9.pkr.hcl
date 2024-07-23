packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  default = "proxmox"
  type    = string
}

variable "ssh_user" {
  default = "admin"
  type    = string
}

variable "ssh_pass" {
  type      = string
  sensitive = true
}

source "proxmox-iso" "rocky9" {
  proxmox_url              = "${var.proxmox_api_url}"
  username                 = "${var.proxmox_api_token_id}"
  token                    = "${var.proxmox_api_token_secret}"
  insecure_skip_tls_verify = true

  node    = "${var.proxmox_node}"
  vm_name = "rocky9"
  vm_id   = "902"

  iso_file = "local:iso/Rocky-9.4-x86_64.iso"

  iso_storage_pool = "local"
  unmount_iso      = true

  qemu_agent = true

  scsi_controller = "virtio-scsi-pci"

  disks {
    disk_size    = "10G"
    format       = "raw"
    storage_pool = "local-lvm"
    type         = "scsi"
  }

  memory = "2048"
  cores  = "1"

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  boot_command = [
    "<up><wait><tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter><wait>"
  ]
  boot      = "c"
  boot_wait = "5s"

  http_directory = "http"

  ssh_username = "${var.ssh_user}"
  ssh_password = "${var.ssh_pass}"
  ssh_timeout  = "20m"
}


