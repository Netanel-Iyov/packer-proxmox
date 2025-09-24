# Ubuntu Server 24.04 Server K8S Node Packer Template on Proxmox
packer {
    required_plugins {
        proxmox = {
            version = ">= 1.1.3"
            source = "github.com/hashicorp/proxmox"
        }
    }
}

# Variable Definitions
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

locals {
    disk_storage = "local-lvm"
}

# Resource Definiation for the VM Template
source "proxmox-iso" "ubuntu-2404-multi-purpose" {
    # Proxmox Connection Settings
    proxmox_url              = var.proxmox_api_url
    username                 = var.proxmox_api_token_id
    token                    = var.proxmox_api_token_secret
    insecure_skip_tls_verify = true

    # VM General Settings
    node                 = "pve"
    vm_id                = "212"
    vm_name              = "ubuntu-2404-multi-purpose-template"
    template_description = "Ubuntu Server 24.04 For Multi-Purpose (Managing K8S Nodes and more)"

    # VM ISO Settings
    boot_iso {
        type         = "scsi"
        iso_file     = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
        unmount      = true
        iso_checksum = "c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
    }

    # VM System Settings
    qemu_agent = true
    cores = 2
    memory = 4096

    # VM Hard Disk Settings
    scsi_controller = "virtio-scsi-single"
    disks {
        disk_size         = "25G"
        format            = "raw"
        storage_pool      = local.disk_storage
        type              = "scsi"
    }

    # VM Network Settings
    network_adapters {
        model    = "virtio"
        bridge   = "vmbr0"
        firewall = "false"
    }

    # VM Cloud-Init Settings
    cloud_init              = true
    cloud_init_storage_pool = local.disk_storage

    # PACKER Boot Commands
    http_directory = "http"
    http_bind_address = "0.0.0.0"
    http_port_min     = 8802
    http_port_max     = 8802

    boot_wait    = "3s"
    boot_command = [
        "c<wait>",
        "linux /casper/vmlinuz --- autoinstall ds=\"nocloud-net;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/\"",
        "<enter><wait>",
        "initrd /casper/initrd",
        "<enter><wait>",
        "boot",
        "<enter>"
    ]

    ssh_username = "niyov"
    ssh_private_key_file = "~/.ssh/id_rsa"
    ssh_timeout = "10m"
}

# Build Definition to create the VM Template
build {
    name    = "ubuntu-2404-multi-purpose"
    sources = ["source.proxmox-iso.ubuntu-2404-multi-purpose"]

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #1
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
            "sudo sync"
        ]
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #2
    provisioner "file" {
        source      = "./files/ubuntu-2404.cfg"
        destination = "/tmp/ubuntu-2404.cfg"
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #3
    provisioner "shell" {
        inline = [ "sudo cp /tmp/ubuntu-2404.cfg /etc/cloud/cloud.cfg.d/ubuntu-2404.cfg" ]
    }

    # Install Ansible
    provisioner "shell" {
        inline = [
            "sudo apt-get update -y",
            "sudo apt-get install -y ansible"
        ]
    }

    # Install Kubernetes (kubectl, kubeadm, kubelet)
    provisioner "shell" {
        inline = [
            "sudo mkdir -p /etc/apt/keyrings",
            "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
            "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
            "sudo apt-get update -y",
            "sudo apt-get install -y kubelet kubeadm kubectl",
            "sudo apt-mark hold kubelet kubeadm kubectl"
        ]
    }

    # Install Docker CE
    provisioner "shell" {
    inline = [
        "sudo apt-get update",
        "sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https",
        "sudo install -m 0755 -d /etc/apt/keyrings",
        "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
        "sudo chmod a+r /etc/apt/keyrings/docker.gpg",
        "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
        "sudo apt-get update",
        "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

        # Enable and start Docker service
        "sudo systemctl enable docker",
        "sudo systemctl start docker"
    ]
    }

    # Final cleanup
    provisioner "shell" {
        inline = [
            "sudo apt-get autoremove -y",
            "sudo apt-get clean",
            "sudo cloud-init clean",
            "sudo rm -rf /var/lib/apt/lists/*"
        ]
    }
}