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

locals {
  user_data = {
    ssh_user = var.ssh_user
    ssh_pass = sha512(var.ssh_pass)
  }
}

source "proxmox-iso" "ubuntu-2404lts-docker" {
  proxmox_url              = "${var.proxmox_api_url}"
  username                 = "${var.proxmox_api_token_id}"
  token                    = "${var.proxmox_api_token_secret}"
  insecure_skip_tls_verify = true

  node    = "${var.proxmox_node}"
  vm_name = "ubuntu-2404lts-docker"
  vm_id   = "902"

  iso_file = "local:iso/ubuntu-24.04-live-server-amd64.iso"

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
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]

  boot      = "c"
  boot_wait = "5s"

  http_content = {
    "/meta-data" = file("http/meta-data")
    "/user-data" = templatefile("http/user-data.tpl", local.user_data)
  }

  ssh_username = var.ssh_user
  ssh_password = var.ssh_pass
  ssh_timeout  = "20m"
}

build {
  name    = "ubuntu-2404lts-docker"
  sources = ["source.proxmox-iso.ubuntu-2404lts-docker"]

  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo rm /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo apt -y autoremove --purge",
      "sudo apt -y clean",
      "sudo apt -y autoclean",
      "sudo cloud-init clean",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo rm -f /etc/netplan/00-installer-config.yaml",
      "sudo sync"
    ]
  }

  provisioner "file" {
    source      = "files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  provisioner "shell" {
    inline = ["sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"]
  }

  provisioner "shell" {
    inline = [
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl start qemu-guest-agent"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get -y install ca-certificates curl",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc",
      "sudo chmod a+r /etc/apt/keyrings/docker.asc",
      "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    ]
  }

}
