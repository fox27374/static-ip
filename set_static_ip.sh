#!/usr/bin/bash
#
# Script to set a static IP address on various Linux distributions.
#
# Currently supported and tested:
# SLES 15, Debian 10, Debian 11, Ubuntu 22.04, Rocky 8, Oracle
#
# Usage:
# ./set_static_ip.sh -i IP -m MASK -g GATEWAY -d DNS -n NTP
# Example:
# ./set_static_ip.sh -i 172.24.88.117 -m 255.255.255.0 -g 172.24.88.254 -d 172.24.85.10,172.24.86.10 -n 172.24.85.10,172.24.86.10
#

NET_IF=""
IP=""
MASK=""
MASK_CIDR=""
GATEWAY=""
DOMAIN=""
DNS=""
NTP=""
DISTRO=""
NET_IF=""
NW_MANAGER=""
IP_FILE=""
DNS_FILE="/etc/resolv.conf"
TIME_FILE=""
TIME_FILE_DIR="/etc/systemd/timesyncd.conf.d"
ROUTE_FILE=""

function print_help()
{
    echo ""
    echo "Usage: $0 -i IP -m MASK -g GATEWAY [-d DNS] [-n NTP]"
    echo ""
    echo -e "\tIP\t\tIP Address e.g. 172.24.85.10"
    echo -e "\tMASK\t\tNetmask e.g. 255.255.255.0"
    echo -e "\tGATEWAY\t\tGateway e.g. 172.24.85.254"
    echo -e "\tDNS\t\tDNS Server (comma separated list) e.g. 172.24.85.10,10.0.0.1"
    echo -e "\tNTP\t\tNTP Server (comma separated list) e.g. 172.24.85.10,10.0.0.1"
    echo -e "\t-h\t\tPrint this help"
    echo ""
    exit 1
}


# get distro name from os-release file
function get_distro()
{
    DISTRO=$(cat /etc/os-release | grep "^NAME" | cut -d "=" -f 2 | tr -d "\"" | tr '[:upper:]' '[:lower:]')
}

# get network interface from ip commande
function get_network_interface()
{
    NET_IF=$(ip a | grep ^2: | cut -d " " -f 2 | tr -d ":")
}

# check if netplan is installed
function get_network_manager()
{
    NW_MANAGER="default"
    if command -v netplan &> /dev/null
    then
        NW_MANAGER="netplan"
    fi
}

# convert mask to CIDR notation
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

# delete all network related config files
function del_config_files()
{
    rm -rf $IP_FILE
    rm -rf $ROUTE_FILE
}


# generate SLES based ip config
function gen_sles_ip_config()
{
    CONFIG="
        BOOTPROTO='static'\n
        IPADDR='$IP'\n
        MTU=''\n
        NAME=''\n
        NETMASK='$MASK'\n
        STARTMODE='auto'\n
        USERCONTROL='no'"

    touch $IP_FILE
    echo -e $CONFIG > $IP_FILE
}


# generate RedHat based ip config
function gen_rh_ip_config()
{
    CONFIG="
        DEVICE='$NET_IF'\n
        NAME='$NET_IF'\n
        ONBOOT='yes'\n
        BOOTPROTO='none'\n
        IPADDR='$IP'\n
        NETMASK='$MASK'\n
        GATEWAY='$GATEWAY'\n
        DNS1='$DNS'"

    touch $IP_FILE
    echo -e $CONFIG > $IP_FILE
}


# generate Debian based IP config
function gen_debian_ip_config()
{
    CONFIG="
        source /etc/network/interfaces.d/*\n\n
        auto lo\n
        iface lo inet loopback\n\n
        allow-hotplug $NET_IF\n
        iface $NET_IF inet static\n
        address $IP\n
        netmask $MASK\n
        gateway $GATEWAY\n"

    if [[ $DNS ]]
    then
        ADD_DNS="dns-nameservers ${DNS[*]}"
    fi

    touch $IP_FILE
    echo -e $CONFIG $ADD_DNS > $IP_FILE
}


# generate Netplan IP config
function gen_netplan_ip_config()
{
    CONFIG="
        network:\n
        \tversion: 2\n
        \tethernets:\n
        \t\t$NET_IF:\n
        \t\t\tdhcp4: no\n
        \t\t\taddresses: ['$IP/$MASK_CIDR']\n
        \t\t\troutes:\n
        \t\t\t\t- to: default\n
        \t\t\t\t\tvia: $GATEWAY\n"

        if [[ $DNS ]]
        then
            DNS_TMP=""
            for NAMESERVER in ${DNS[@]}
            do
                DNS_TMP=$DNS_TMP\'$NAMESERVER\',
            done

            DNS_TMP=${DNS_TMP::-1}
            ADD_DNS="
                \t\t\tnameservers:\n
                \t\t\t\taddresses: [$DNS_TMP]"
        fi

    #touch $IP_FILE
    #echo -e $CONFIG $ADD_DNS | sed 's/\t/  /g' > $IP_FILE
    echo -e $CONFIG $ADD_DNS | sed 's/\t/  /g'
}

# generate timesyncd config
function gen_timesyncd_config()
{
    CONFIG="
        [Time]\n
        NTP=${NTP[*]}"

    mkdir -p $TIME_FILE_DIR
    touch $TIME_FILE
    echo -e $CONFIG > $TIME_FILE
}

# generate resolv.conf file
function gen_resolv_config()
{
    RESOLVE=""
    for NAMESERVER in ${DNS[@]}
        do
            RESOLVE=$RESOLVE"nameserver "$NAMESERVER"\n"
        done
    
    RESOLVE=${RESOLVE::-2}

    touch $DNS_FILE
    echo -e $RESOLVE > $DNS_FILE
}

# generate routes file for SLES
function gen_routes()
{
    ROUTE="default $GATEWAY - $NET_IF"
    touch $ROUTE_FILE
    echo -e $ROUTE > $ROUTE_FILE
}

# generate network related files based on the Linux distribution
function gen_ip_config()
{
    get_distro
    get_network_interface
    get_network_manager

    if [[ "$DISTRO" =~ "sles" ]]
    then
        IP_FILE="/etc/sysconfig/network/ifcfg-$NET_IF"
        ROUTE_FILE="/etc/sysconfig/network/routes"
        del_config_files
        gen_sles_ip_config
        gen_routes

    elif [[ "$DISTRO" =~ "rocky" ]] || [[ "$DISTRO" =~ "oracle" ]]
    then
        IP_FILE="/etc/sysconfig/network-scripts/ifcfg-$NET_IF"
        del_config_files
        gen_rh_ip_config
        nmcli con reload
        nmcli con down $NET_IF && nmcli con up $NET_IF

    elif [[ "$DISTRO" =~ "debian" ]] || [[ "$DISTRO" =~ "ubuntu" ]]
    then
        if [[ "$NW_MANAGER" == "netplan" ]]
        then
            rm -rf "/etc/netplan/50-cloud-init.yaml"
            IP_FILE="/etc/netplan/10-ubuntu.yaml"
            TIME_FILE="/etc/systemd/timesyncd.conf.d/10-ntp.conf"
            del_config_files
            gen_netplan_ip_config
            gen_timesyncd_config
            netplan apply
        else
            IP_FILE="/etc/network/interfaces"
            TIME_FILE="/etc/systemd/timesyncd.conf.d/10-ntp.conf"
            del_config_files
            gen_debian_ip_config
            gen_timesyncd_config
            ifdown $NET_IF; ifup $NET_IF
        fi
    fi
}

# check args and print help
while getopts ":h:i:m:g:d:n:" OPTIONS; do
    case ${OPTIONS} in
        h)
            print_help
            ;;
        i)
            IP=${OPTARG}
            ;;
        m)
            MASK=${OPTARG}
            convert_mask
            ;;
        g)
            GATEWAY=${OPTARG}
            ;;
        d)
            DNS_ARRAY=${OPTARG}
            readarray -d , -t DNS <<< "$DNS_ARRAY"
            ;;
        n)
            NTP_ARRAY=${OPTARG}
            readarray -d , -t NTP <<< "$NTP_ARRAY"
            ;;
        :)
            echo "Error: -${OPTARG} requires an argument."
            exit 1
            ;;
        *)
            print_help
            ;;
    esac
done


if [[ $IP ]] && [[ $MASK ]] && [[ $GATEWAY ]]
then
    gen_ip_config
    gen_netplan_ip_config
else
    echo -e "Not all arguments supplied"
fi

if [[ $DNS ]]
then
    rm -rf $DNS_FILE
    gen_resolv_config
fi

if [[ $NTP ]]
then
    mkdir -p $TIME_FILE_DIR
    systemctl restart systemd-timesyncd
fi
