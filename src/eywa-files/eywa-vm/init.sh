#!/bin/bash

## root 계정 비번 제거
sed -i '/root/d' /etc/shadow
echo "root:!:16038:0:99999:7:::" >> /etc/shadow

echo "
acpiphp
pci_hotplug" >> /etc/modules
for m in acpiphp pci_hotplug; do sudo modprobe ${m}; done

if [ ! -z $PASSWD ]; then
	echo "root:$PASSWD" | chpasswd
	#echo "password" | passwd --stdin root
fi

cp -f /usr/share/zoneinfo/Asia/Seoul /etc/localtime

## HOSTNAME 설정
#HOSTNAME="EYWA-VM-${ONE_UID}-`echo $ETH0_IP | sed 's/\./-/g'`"
HOSTNAME="VM-${ONE_UID}-`echo $ETH0_IP | sed 's/\./-/g'`"
echo "$HOSTNAME.test.org" > /etc/hostname
echo "$ETH0_IP $HOSTNAME.test.org $HOSTNAME" >> /etc/hosts
#echo "127.0.0.1 $HOSTNAME.test.org $HOSTNAME" >> /etc/hosts
/etc/init.d/hostname restart
hostname $HOSTNAME.test.org
service rsyslog restart

echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /etc/resolvconf/resolv.conf.d/head 

## Set MTU to 1450 (for VXLAN)
sed -i '/^exit 0/d' /etc/rc.local
echo "ifconfig eth0 mtu 1450" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
ifconfig eth1 mtu 1450

HOME="/root"
#mkdir -p $HOME/.ssh
rm -rf $HOME/.ssh 2> /dev/null
cp -a /mnt/.ssh $HOME/
chmod 644 $HOME/.ssh/*
chmod 600 $HOME/.ssh/id_rsa
echo $SSH_PUBLIC_KEY >> $HOME/.ssh/authorized_keys
chown -R root:root $HOME

/etc/init.d/networking restart

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

## for Test Apache
cp -a /var/www/index.html /var/www/index.html.default
mkdir -p /var/www/ 2> /dev/null
echo "
<html>
<body>
<h1>
$(hostname)
$(ifconfig eth0 | awk '/inet addr/ {print $2}' | cut -d: -f2)
</h1>
</body>
</html>
" > /var/www/index.html
#pushd /home/test-web
#python -m SimpleHTTPServer 80 &
#popd
service apache2 start
update-rc.d apache2 enable

update-rc.d vmcontext disable
