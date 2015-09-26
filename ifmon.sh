#!/usr/bin/sh

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

for i in eth0 tun0; do
    sysctl -w net.ipv4.conf.$i.rp_filter=2
done
egrep -q '^10[[:space:]]+eth0$' /etc/iproute2/rt_tables || echo "10 eth0" | tee -a /etc/iproute2/rt_tables > /dev/null

# populate tables
ip route flush table eth0
ip route add default via 192.168.1.2 dev eth0 table eth0

result=0
while [ $result -eq 0 ]; do
    ip rule del fwmark 0xa/0xf lookup eth0 2>/dev/null
    result=$?
done

ip rule add fwmark 0xa/0xf lookup eth0

ping -q -m 10 8.8.8.8 -c 1 -W 5
result=$?

if [ $result -ne 0 ]; then
    >&2 echo "Failed to ping from eth0. eth0 network is down?"
    # would down/up eth0 here; Marvell hw issue.
fi

ping -q 8.8.8.8 -c 1 -W 5
result=$?

if [ $result -ne 0 ]; then
    >&2 echo "Failed to ping from eth0. Network is down?"
    # would restart VPN here
fi

#!@todo wait for vpn restart. Is there a trigger when OpenVPN establishes new routes?
