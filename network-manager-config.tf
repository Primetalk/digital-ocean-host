resource "local_file" "network-manager-config" {
  filename = "remote-host-vpn-connection"
  content = <<EOF
[connection]
id=remote-host-1
uuid=88599b3a-ab02-480a-aa65-4bcfa81f4dac
type=vpn
autoconnect=false
permissions=
secondaries=

[vpn]
ta-dir=1
connection-type=tls
remote=${digitalocean_droplet.remote-host.ipv4_address}
cipher=AES-256-CBC
keysize=256
cert-pass-flags=0
cert=${path.module}/openvpn-ca/keys/client1.crt
ca=${path.module}/openvpn-ca/keys/ca.crt
key=${path.module}/openvpn-ca/keys/client1.key
ta=${path.module}/openvpn-ca/keys/ta.key
service-type=org.freedesktop.NetworkManager.openvpn

[vpn-secrets]
no-secret=true

[ipv4]
dns-search=
method=auto

[ipv6]
addr-gen-mode=stable-privacy
dns-search=
ip6-privacy=0
method=auto
EOF
}

resource "local_file" "network-manager-config-export" {
  filename = "remote-host-vpn-connection-export.conf"
  content = <<EOF
 client
 remote '${digitalocean_droplet.remote-host.ipv4_address}'
 ca '${path.module}/openvpn-ca/keys/ca.crt'
 cert '${path.module}/openvpn-ca/keys/client1.crt'
 key '${path.module}/openvpn-ca/keys/client1.key'
 cipher AES-256-CBC
 keysize 256
 dev tun
 proto udp
 tls-auth '${path.module}/openvpn-ca/keys/ta.key' 1
 nobind
 auth-nocache
 script-security 2
 persist-key
 persist-tun
 user nobody
 group nogroup
EOF
}

output "cmd to import remote-host-vpn-connection" {
  value = "nmcli connection import type openvpn file remote-host-vpn-connection-export.conf"
//  value = "FILE=/etc/NetworkManager/system-connections/remote-host-vpn-connection; sudo cp remote-host-vpn-connection $FILE; sudo chmod 600 $FILE"
}