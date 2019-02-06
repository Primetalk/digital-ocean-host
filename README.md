# Digital ocean VPN remote host

This project aims at creating a remote host that runs OpenVPN. 
The idea is to instantiate the remote instance on demand, configure it using
terraform script and destroy after use.

There are following concerns that need to be addressed:

- obtain access token for Digital Ocean (this project uses DO cloud as the most competitive at the moment);
- add SSH public key to DO account;
- obtain id of SSH key from DO (fingerprint is not enough) using REST API;
- generate certification authority and keys for client and server;
- instantiate a remote instance ("droplet");
- use instance via SSH; 
- deploy server keys;
- configure remote user on the remote server; (optional, only if we want to login to the remote machine)
- configure OpenVPN (with default configuration);
- enable routing and NAT;
- make sure that DNS is provided by VPN and is being used by client connection;
- generate configuration of the local connection to OpenVPN (using NetworkManager);

We cannot fully trust the remote instance. And we are going to recreate such instances 
on demand. So we need a separate certification authority that will yield certificates
for the new instances.

## DigitalOcean aspects

### Obtain access token for DO

Use UI https://cloud.digitalocean.com/account/api/tokens

Find token and put it into `terraform.tfvars` file.
Also add it to command line:
```bash
export DO_TOKEN=12345600000000000000000000123410234131
```

### Add SSH public key to DO account

Use UI https://cloud.digitalocean.com/account/security.

Find fingerprint and put it into `terraform.tfvars` file.

### Obtain ssh key id from DigitalOcean

In order to connect to a droplet with a key saved in DigitalOcean, one need to know it's `id`.
It could be obtained using DO API: 

```bash
export DO_TOKEN=12345600000000000000000000123410234131
curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $DO_TOKEN" "https://api.digitalocean.com/v2/account/keys" | jq ".ssh_keys[0].id"
```

This id should be set to the appropriate variable in `terraform.tfvars` file.


## Certification authority: keys and certificates for client and server

### Create local certification authority

(mostly from https://www.digitalocean.com/community/tutorials/openvpn-ubuntu-16-04-ru)

```bash
cd terraform
make-cadir openvpn-ca
cd openvpn-ca/
```

We should update some of the field variables with our data:

```bash
tee -a vars <<EOF
export KEY_ORG="DigitalOceanRemoteHost"
export KEY_EMAIL="admin@remote.host.com"
export KEY_OU="RemoteHost"
export KEY_CN="RemoteHostCommonName"
export KEY_ALTNAMES="RemoteHostAltName"
EOF
```

Then remove old values (DON'T do it without backup!)
```bash
# ./clean-all
```

Create root CA:

```bash
./build-ca
```

It'll ask the questions with default values configured above. So nothing needs to be changed.

As a result it'll generate `ca.key` - private key that will be used for signing certificates
issued by this certification authority.

### Generate server certificate and key pair


```bash
./build-key-server remotehost
```

It'll ask some metainformation and a couple of acknowledgements. There is no need
to change anything here. Just acknowledge.

And generate Diffie-Helman keys
```bash
./build-dh
```

(It takes a couple of minutes.)

Generate HMAC:
```bash
openvpn --genkey --secret keys/ta.key
```
As a result we'll have remotehost key certificate request and other files:
```
$ ls -1 keys/
01.pem
ca.crt
ca.key
dh2048.pem
index.txt
index.txt.attr
index.txt.old
remotehost.crt
remotehost.csr
remotehost.key
serial
serial.old
ta.key
```
We'll need to copy at least 3 files - key,certificate and certification authority certificate:
ca.crt
remotehost.crt
remotehost.key

This is performed using file provisioner in `main.tf`.


### Issuing client certificates

```bash
source vars
export KEY_ORG="DigitalOceanLocalHost"
export KEY_EMAIL="admin@local.host.com"
export KEY_OU="LocalHost"
export KEY_CN="LocalHostCommonName"
export KEY_ALTNAMES="LocalHostAltName"
ln -s openssl-1.0.0.cnf openssl.cnf
./build-key client1
```

This command will create client1.csr, client1.key, client1.crt.

## Instantiate a "droplet"

Issue
```bash
terraform init
terraform apply
```

(Or just `... apply` on subsequent calls.)

This command will create an instance and configure there an OpenVPN server with default configuration.

See `main.tf` for details of what is being done.

The terraform script will also generate import file for NetworkManager. This file could be imported
 
```bash
nmcli connection import type openvpn file remote-host-vpn-connection-export.conf
```

## Using instance via SSH

### Using ssh keys with passwords

In order to enable ssh key with password for terraform, one might use ssh-agent:

```bash
ssh-add
```
This command will ask for password to key and remeber it in the running ssh-agent.


### Local SSH SOCKS 5 server

(As a lightweight secure tunnel):
```bash
autossh -M 0 -N -D 9999 112.333.444.555 
```

Then it can be configured as SOCKS5 server `localhost:9999` in browsers. 

To check OpenVPN status on server consult `/var/log/openvpn/openvpn-status.log`


## Using OpenVPN

While server is running anyone with a key signed by the same certification authority can connect using
and OpenVPN client and use this VPN. 

### Routing on local machine

There might be some issues with routing on the local machine. In particular, after connection
is established it tries to route the address of the remote host via VPN. And fails. 
To exclude this address from routing we should send it to the default client's router:  
```bash
sudo ip ro add 12.34.56.78/32 via 192.168.1.1 dev eth0
```

### DNS troubleshooting

See https://askubuntu.com/questions/1032476/ubuntu-18-04-no-dns-resolution-when-connected-to-openvpn
```bash
sudo apt install openvpn-systemd-resolved
```
(NB! It'll remove `systemd-shim`.)
The rest is included in the generated vpn configuration.
