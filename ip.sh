#!/bin/bash
FILE="/tmp/guestinfo.xml"
NETPLAN_FILE="/etc/netplan/50-static.yaml"

# Get VM Infos
vmtoolsd --cmd 'info-get guestinfo.ovfEnv' > $FILE

# Get local interface
NET_IF=$(ip a | grep ^2: | cut -d " " -f 2 | tr -d ":")

# Extract network/ip infos
IP=$(sed -n 's/.*Property oe:key="guestinfo.interface.0.ip.0.address" oe:value="\([^"]*\).*/\1/p' $FILE)
MASK=$(sed -n 's/.*Property oe:key="guestinfo.interface.0.ip.0.netmask" oe:value="\([^"]*\).*/\1/p' $FILE)
GATEWAY=$(sed -n 's/.*Property oe:key="guestinfo.interface.0.route.0.gateway" oe:value="\([^"]*\).*/\1/p' $FILE)
DNS=$(sed -n 's/.*Property oe:key="guestinfo.dns.servers" oe:value="\([^"]*\).*/\1/p' $FILE)

# Convert mask to CIDR notation
function convert_mask()
{
    case $MASK in
        255.255.0.0) MASK_CIDR=16 ;;
        255.255.128.0) MASK_CIDR=17 ;;
        255.255.192.0) MASK_CIDR=18 ;;
        255.255.224.0) MASK_CIDR=19 ;;
        255.255.240.0) MASK_CIDR=20 ;;
        255.255.248.0) MASK_CIDR=21 ;;
        255.255.252.0) MASK_CIDR=22 ;;
        255.255.254.0) MASK_CIDR=23 ;;
        255.255.255.0) MASK_CIDR=24 ;;
        255.255.255.128) MASK_CIDR=25 ;;
        255.255.255.192) MASK_CIDR=26 ;;
        255.255.255.224) MASK_CIDR=27 ;;
        255.255.255.240) MASK_CIDR=28 ;;
        255.255.255.248) MASK_CIDR=29 ;;
        255.255.255.252) MASK_CIDR=30 ;;
        255.255.255.254) MASK_CIDR=31 ;;
        255.255.255.255) MASK_CIDR=32 ;;
    esac
}

convert_mask

# Write netplan yaml
cat > $NETPLAN_FILE <<EOF
network:
  version: 2
  ethernets:
    $NET_IF:
      dhcp4: no
      addresses: ['$IP/$MASK_CIDR']
      routes:
	- to: default
	  via: $GATEWAY
      nameservers:
        addresses : [$DNS]
EOF
