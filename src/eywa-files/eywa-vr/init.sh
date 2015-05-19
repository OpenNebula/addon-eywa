#!/bin/bash

#. /mnt/context.sh

history -c

## root 계정 비번 제거
#sed -i '/vyatta/d' /etc/shadow
#echo "root:!:16048:0:99999:7:::" >> /etc/shadow

## root 계정 비번 설정
if [ ! -z $PASSWD ]; then
	echo "root:$PASSWD" | chpasswd 			## for Debian/Ubunut
	#echo "password" | passwd --stdin root	## for RHEL/CentOS
fi

cp -f /usr/share/zoneinfo/Asia/Seoul /etc/localtime

echo "
acpiphp
pci_hotplug" >> /etc/modules
for m in acpiphp pci_hotplug; do sudo modprobe ${m}; done

## HOSTNAME 설정
#HOSTNAME="EYWA-VR-${ONE_UID}-`echo $ETH0_IP | sed 's/\./-/g'`"
HOSTNAME="VR-${ONE_UID}-`echo $ETH0_IP | sed 's/\./-/g'`"
echo "$HOSTNAME.test.org" > /etc/hostname
echo "$ETH0_IP $HOSTNAME.test.org $HOSTNAME" >> /etc/hosts
#echo "127.0.0.1 $HOSTNAME.test.org $HOSTNAME" >> /etc/hosts
/etc/init.d/hostname restart
hostname $HOSTNAME.test.org
service rsyslog restart

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/ip_forward.conf
sysctl -p /etc/sysctl.d/ip_forward.conf

echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /etc/resolvconf/resolv.conf.d/head 

HOME="/root"
#mkdir -p $HOME/.ssh
rm -rf $HOME/.ssh 2> /dev/null
cp -a /mnt/.ssh $HOME/
chmod 644 $HOME/.ssh/*
chmod 600 $HOME/.ssh/id_rsa
echo $SSH_PUBLIC_KEY >> $HOME/.ssh/authorized_keys
chown -R root:root $HOME

## == (추후 VR 이미지에 설정 해야할지 고민 필요... 선택사항이 아닌 필수라...) ===
sed -i '/^exit 0/d' /etc/rc.local
ifconfig eth1 mtu 1450
echo "ifconfig eth1 mtu 1450" >> /etc/rc.local
echo "iptables-restore < /etc/default/iptables.rules" >> /etc/rc.local
echo "ip addr add 10.0.0.1/8 dev eth1" >> /etc/rc.local
echo "arping -U 10.0.0.1 -I eth1 -c 100 &" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
ip addr add 10.0.0.1/8 dev eth1
#arping -A -U 10.0.0.1 -I eth1 -c 100 &
arping -A 10.0.0.1 -I eth1 -c 100 &
cp -f /mnt/iptables.rules /etc/default/iptables.rules
iptables-restore < /etc/default/iptables.rules
cp -f /mnt/haproxy.cfg.tmpl /etc/haproxy/haproxy.cfg.tmpl
cp -f /mnt/haproxy-cfg-gen /etc/haproxy/haproxy-cfg-gen
sed -i "s/@@__PASS__@@/${PASSWD}/g" /etc/haproxy/haproxy-cfg-gen
cp -f /mnt/haproxy.init /etc/init.d/haproxy
rm -rf /etc/haproxy/haproxy.cfg /etc/haproxy/cfg.d
mkdir -p /etc/haproxy/cfg.d
/etc/haproxy/haproxy-cfg-gen
#if [ "${HAPROXY_CFG}X" != "X" ]; then
#	/etc/init.d/haproxy start
#else
#	/etc/init.d/haproxy stop
#fi
service haproxy stop
update-rc.d haproxy enable

umount -l /mnt

CODENAME=`lsb_release -a 2> /dev/null| awk '/^Codename/ {print $2}'`
if [ $CODENAME == "precise" ]; then
echo "### Internal apt-get Mirror
deb http://ftp.daum.net/ubuntu precise main restricted universe
deb http://ftp.daum.net/ubuntu precise-updates main restricted universe
deb http://ftp.daum.net/ubuntu precise-security main restricted universe multiverse" > /etc/apt/sources.list
elif [ $CODENAME == "trusty" ]; then
echo "### Internal apt-get Mirror
deb http://ftp.daum.net/ubuntu/ trusty main restricted universe multiverse
deb http://ftp.daum.net/ubuntu/ trusty-updates main restricted universe multiverse
deb http://ftp.daum.net/ubuntu/ trusty-security main restricted universe multiverse
#deb http://ftp.daum.net/ubuntu/ trusty-backports main restricted universe multiverse" > /etc/apt/sources.list
fi

service apache2 stop
update-rc.d apache2 disable

update-rc.d vmcontext disable
