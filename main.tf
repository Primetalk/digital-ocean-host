# Set the variable value in *.tfvars file
# or using -var="do_token=..." CLI option
variable "do_token" {}
variable "user" {}
variable "ssh_public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}
variable "ssh_key_do_id" {}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = "${var.do_token}"
}

# Create a remote-host server
# See https://developers.digitalocean.com/documentation/v2/#sizes for various sizes
resource "digitalocean_droplet" "remote-host" {
  image  = "ubuntu-18-04-x64"
  name   = "remote-host-1"
  region = "fra1" //Frankfurt, Germany "nyc3" - New York, US
  size   = "s-1vcpu-1gb"
  ssh_keys = ["${var.ssh_key_do_id}"]

  connection {
    agent = true
    user = "root"
  }
  provisioner "remote-exec" {
    inline = [
      // Create admin user
//      "adduser --disabled-password --quiet --gecos ${var.user}",
//      "adduser --quiet ${var.user} sudo",
      // allow ssh connection
//      "mkdir -p /home/${var.user}/.ssh/",
      "apt-get -y install openvpn"
      // Do we need easy-rsa?
    ]
  }
  provisioner "file" { source = "openvpn-ca/keys/remotehost.crt" destination = "/etc/openvpn/server.crt" }
//  provisioner "file" { source = "openvpn-ca/keys/remotehost.csr" destination = "/etc/openvpn/keys/server.csr" }
  provisioner "file" { source = "openvpn-ca/keys/remotehost.key" destination = "/etc/openvpn/server.key" }
  provisioner "file" { source = "openvpn-ca/keys/ca.crt"         destination = "/etc/openvpn/ca.crt" }
  provisioner "file" { source = "openvpn-ca/keys/ta.key"         destination = "/etc/openvpn/ta.key" }
  provisioner "file" { source = "openvpn-ca/keys/dh2048.pem"     destination = "/etc/openvpn/dh2048.pem" }
//  provisioner "file" { source = "${var.ssh_public_key_path}"     destination = "/home/${var.user}/.ssh/authorized_keys" }

  provisioner "remote-exec" {
    inline = [
      // Configure user
//      "chown ${var.user}:${var.user} /home/${var.user}/.ssh/authorized_keys",
//      "chmod 0600 /home/${var.user}/.ssh/authorized_keys",
      // secure access to keys
      "chmod 0400 /etc/openvpn/server.key",
      "chmod 0400 /etc/openvpn/ta.key",
      // configure openvpn. We use default configuration
      "gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz > /etc/openvpn/server.conf",
      // Configure OpenVPN to Route DNS via VPN
      "echo '' | tee -a /etc/openvpn/server.conf",
      "echo 'push \"dhcp-option DNS 8.8.8.8\"' | tee -a /etc/openvpn/server.conf",
      "echo 'push \"dhcp-option DOMAIN-ROUTE .\"' | tee -a /etc/openvpn/server.conf",
      "echo 'push \"redirect-gateway local def1\"' | tee -a /etc/openvpn/server.conf",
      // Enable IPv4 forwarding
      "echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf",
      // Configuring NAT
      "iptables --table nat --append POSTROUTING --out-interface eth0 -j MASQUERADE",
      // restarting sysctl
      "sysctl -p",
      // start openvpn server
      "systemctl start openvpn@server"
//      "echo ${file(var.ssh_public_key_path)} >> /home/${var.user}/.ssh/authorized_keys",
//      "apt-get update",
//      "apt-get install openvpn easy-rsa"
    ]
  }
  provisioner "local-exec" { command = "nmcli connection import type openvpn file remote-host-vpn.conf" }
//  provisioner "local-exec" { command = "sudo ip ro add ${digitalocean_droplet.remote-host.ipv4_address}/32 via 192.168.1.1 dev eth0" }
}

output "ip" {
  value = "${digitalocean_droplet.remote-host.ipv4_address}"
}

output "ip ro" {
  value = "sudo ip ro add ${digitalocean_droplet.remote-host.ipv4_address}/32 via 192.168.1.1"
}

output "ssh-socks" {
  value = "autossh -M 0 -N -D 9999 root@${digitalocean_droplet.remote-host.ipv4_address}"
}

output "ssh" {
  value = "ssh root@${digitalocean_droplet.remote-host.ipv4_address}"
}
