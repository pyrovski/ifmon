#!/usr/bin/sh

# The idea is to monitor the physical connection, the Internet
# connection, and the tunnel connection without relying on the default
# routing table. We do this by creating our own routing table and
# carefully choosing the hosts that we check. 

# First, check the physical connection by copying its associated routes
# to a new table. 

phys=eth0
tun=tun0

veth_sub=10.10.1

nsexec (){
  ip netns exec novpn $*
}

InternetTarget=8.8.8.8

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

for i in $phys tun0; do
    sysctl -w net.ipv4.conf.$i.rp_filter=2 >/dev/null
done
egrep -q '^10[[:space:]]+'$phys'$' /etc/iproute2/rt_tables || echo "10 $phys" | tee -a /etc/iproute2/rt_tables > /dev/null

# populate tables
ip route flush table $phys

# copy main table rules for physical interface
ip route | egrep -o ".* dev *$phys "  | xargs -i bash -c "ip r a t $phys {}"

# create a network namespace
ip netns show | egrep '^novpn$' >/dev/null || ip netns add novpn

# create a veth pair
ip link del dev ifmon1 2>&1 > /dev/null
ip link add dev ifmon1 type veth peer name ifmon2
ip link set dev ifmon2 netns novpn
ip addr add $veth_sub.1/24 dev ifmon1
nsexec ip addr add $veth_sub.2/24 dev ifmon2
ip link set dev ifmon1 up
nsexec ip link set dev ifmon2 up

# add some routes for netns
nsexec ip route add default via $veth_sub.1
ip route add $veth_sub.0/24 dev ifmon1 table $phys

# enable MASQUERADE for our netns
rule="POSTROUTING -t nat -s $veth_sub.0/24 -j MASQUERADE"
iptables -C $rule 2>/dev/null || iptables -A $rule

result=0
while [ $result -eq 0 ]; do
    ip rule del from $veth_sub.0/24 lookup $phys 2>/dev/null
    result=$?
done

ip rule add from $veth_sub.0/24 lookup $phys 2>/dev/null

nsexec ping -q -m 10 $InternetTarget -c 1 -W 5 2>&1 >/dev/null
result=$?

if [ $result -ne 0 ]; then
    >&2 echo "Failed to ping from $phys. $phys network is down?"
    # would down/up $phys here; Marvell hw issue.
fi

# check Internet through physical connection

nsexec ping -q $InternetTarget -c 1 -W 5 2>&1 >/dev/null
result=$?

if [ $result -ne 0 ]; then
	>&2 echo "Failed to ping from $phys. Internet is down?"
	exit 1
fi

# check tunnel

# there has to be a better way to get the IP address of the other tunnel endpoint
tunnel_ep=`ip route | grep -v '/' | egrep 'via .* *dev *tun0 *' | awk '{print $3}'`
ping $tunnel_ep -I $tun -r -c 1 -W 5 2>&1 >/dev/null
result=$?
if [ $result -ne 0 ]; then
	>&2 echo "Failed to ping $tun endpoint $tunnel_ep. $tun is down?"
	# restart tunnel
	service=`systemctl | grep pia@  | awk '{print $1}'`
	>&2 echo "Restarting tunnel $service"
	systemctl restart $service
fi

#!@todo wait for vpn restart. Is there a trigger when OpenVPN establishes new routes?
