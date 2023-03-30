#!/usr/bin/bash

# Script to set a static IP address on various Linux distributions.
#
# Currently supported and tested:
# SLES 15, Debian 10, Debian 11, Ubuntu 22.04, Rocky 8, Oracle
#
# Usage:
# ./set_static_ip.sh IP MASK GATEWAY DNS NTP
# Example:
# ./set_static_ip.sh 172.24.88.117 255.255.255.0 172.24.88.254 172.24.85.10,172.24.86.10 172.24.85.10,172.24.86.10
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
    echo "Usage: $0 IP MASK GATEWAY DNS [DOMAIN]"
    echo ""
    echo -e "\tIP\t\tIP Address"
    echo -e "\tMASK\t\tNetmask"
    echo -e "\tGATEWAY\t\tGateway"
    echo -e "\tDNS\t\tDNS Server (comma separated)"
    echo -e "\tNTP\t\tNTP Server (comma separated)"
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
    #rm -rf $DNS_FILE
    rm -rf $ROUTE_FILE
}


# generate SLES based ip config
function gen_sles_ip_config()
{
    CONFIG="\n
        BOOTPROTO='static'\n
        IPADDR='$IP'\n
        MTU=''\n
        NAME=''\n
        NETMASK='$MASK'\n
        STARTMODE='auto'\n
        USERCONTROL='no'\n
        "
    touch $IP_FILE
    echo -e $CONFIG > $IP_FILE
}


# generate RedHat based ip config
function gen_rh_ip_config()
{
    CONFIG="\n
        DEVICE='$NET_IF'\n
        NAME='$NET_IF'\n
        ONBOOT='yes'\n
        BOOTPROTO='none'\n
        IPADDR='$IP'\n
        NETMASK='$MASK'\n
        GATEWAY='$GATEWAY'\n
        DNS1='$DNS'
        "

    touch $IP_FILE
    echo -e $CONFIG > $IP_FILE
}


# generate Debian based IP config
function gen_debian_ip_config()
{
    CONFIG="\n
        source /etc/network/interfaces.d/*\n\n
        auto lo\n
        iface lo inet loopback\n\n
        allow-hotplug $NET_IF\n
        iface $NET_IF inet static\n
        address $IP\n
        netmask $MASK\n
        gateway $GATEWAY\n
        dns-nameservers ${DNS[*]}\n
        "
    touch $IP_FILE
    echo -e $CONFIG > $IP_FILE
}


# generate Netplan IP config
function gen_netplan_ip_config()
{
    DNS_TMP=""
    for NAMESERVER in ${DNS[@]}
        do
            DNS_TMP=$DNS_TMP\'$NAMESERVER\',
        done

    DNS_TMP=${DNS_TMP::-1}

    CONFIG="\n
        network:\n
        \tversion: 2\n
        \tethernets:\n
        \t\t$NET_IF:\n
        \t\t\tdhcp4: no\n
        \t\t\taddresses: ['$IP/$MASK_CIDR']\n
        \t\t\troutes:\n
        \t\t\t\t- to: default\n
        \t\t\t\t\tvia: $GATEWAY\n
        \t\t\tnameservers:\n
        \t\t\t\taddresses: [$DNS_TMP]\n
        "

    touch $IP_FILE
    echo -e $CONFIG  | sed 's/\t/  /g' > $IP_FILE
}

# generate timesyncd config
function gen_timesyncd_config()
{
    CONFIG="\n
        [Time]\n
        NTP=${NTP[*]}"

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
    #if [[ "$DOMAIN" ]]
    #then
    #    ADD="\n
    #    domain $DOMAIN\n
    #    search $DOMAIN"
    #fi

    touch $DNS_FILE
    #echo -e $RESOLVE $ADD > $DNS_FILE
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
        gen_resolv_config

    elif [[ "$DISTRO" =~ "rocky" ]] || [[ "$DISTRO" =~ "oracle" ]]
    then
        IP_FILE="/etc/sysconfig/network-scripts/ifcfg-$NET_IF"
        del_config_files
        gen_rh_ip_config
        gen_resolv_config
        nmcli con reload
        nmcli con down $NET_IF && nmcli con up $NET_IF

    elif [[ "$DISTRO" =~ "debian" ]] || [[ "$DISTRO" =~ "ubuntu" ]]
    then
        if [[ "$NW_MANAGER" == "netplan" ]]
        then
            rm -rf "/etc/netplan/50-cloud-init.yaml"
            IP_FILE="/etc/netplan/10-ubuntu.yaml"
            TIME_FILE="/etc/systemd/timesyncd.conf.d/10-ntp.conf"
            mkdir -p $TIME_FILE_DIR
            convert_mask
            del_config_files
            gen_netplan_ip_config
            gen_timesyncd_config
            #gen_resolv_config
            netplan apply
            systemctl restart systemd-timesyncd
        else
            IP_FILE="/etc/network/interfaces"
            TIME_FILE="/etc/systemd/timesyncd.conf.d/10-ntp.conf"
            mkdir -p $TIME_FILE_DIR
            del_config_files
            gen_debian_ip_config
            gen_timesyncd_config
            gen_resolv_config
            systemctl restart systemd-timesyncd
        fi
    fi
}

# check args and print help
case $1 in
    -h)
        print_help
        ;;
    *)
        if [[ $1 ]] && [[ $2 ]] && [[ $3 ]] && [[ $4 ]] && [[ $5 ]]
        then
            # get input args
            IP=$1
            MASK=$2
            GATEWAY=$3
            DNS_ARRAY=$4
            NTP_ARRAY=$5

            readarray -d , -t DNS <<< "$DNS_ARRAY"
            readarray -d , -t NTP <<< "$NTP_ARRAY"

            # generate distro specific config
            gen_ip_config
        else
            print_help
        fi
        ;;
esac

