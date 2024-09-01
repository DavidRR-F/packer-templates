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

source "proxmox-iso" "ubuntu-2404lts-k8s" {
  proxmox_url              = "${var.proxmox_api_url}"
  username                 = "${var.proxmox_api_token_id}"
  token                    = "${var.proxmox_api_token_secret}"
  insecure_skip_tls_verify = true

  node    = "${var.proxmox_node}"
  vm_name = "ubuntu-2404lts-k8s"
  vm_id   = "903"

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
  name    = "ubuntu-2404lts-k8s"
  sources = ["source.proxmox-iso.ubuntu-2404lts-k8s"]

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
      "sudo systemctl stop ufw",
      "sudo systemctl disable ufw",
      "sudo sed -i '/ swap /s/^/#/' /etc/fstab",
      "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt install -y apt-transport-https ca-certificates curl gnupg containerd",
      "sudo mkdir /etc/containerd",
      "sudo chmod 755 /etc/containerd",
      "containerd config default > /etc/containerd/config.toml",
      "sudo sed -i '/^.*SystemdCgroup.*$/c\\            SystemdCgroup = true' /etc/containerd/config.toml",
      "sudo systemctl restart containerd",
      "echo 'br_netfilter' >> /etc/modules-load.d/k8s.conf",
      "modprobe br_netfilter",
      "echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.d/k8s.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables=1' >> /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system"
    ]
  }

  provisioner "shell" {
    inline = [
      "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "sudo apt install -y kubeadm kubelet kubectl",
      "sudo systemctl enable --now kubelet"
    ]
  }

}
