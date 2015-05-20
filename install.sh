#!/bin/bash

if [ "$(whoami)" != "root" ]; then
	echo
	echo "[ERROR] Retry command, by [root] user...."
	exit 1
fi

ONE_CONF=${ONE_USER:-/etc/one/oned.conf}
ONE_USER=${ONE_USER:-oneadmin}
ONE_VAR=${ONE_VAR:-/var/lib/one}
ONE_LIB=${ONE_LIB:-/usr/lib/one}
ONE_LOG=${ONE_LOG:-/var/log/one}

if [ -n "$ONE_LOCATION" ]; then
    ONE_VAR="$ONE_LOCATION/var"
    ONE_LIB="$ONE_LOCATION/lib"
fi

#------------------------------------------------------

echo

## Backup oned.conf
cp -a ${ONE_CONF} ${ONE_CONF}.`date +%Y%m%d_%H%M%S`

#front_ip=$(/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')

modprobe vxlan 2>/dev/null
RESULT=$?
if [ ${RESULT} -ne 0 ]; then
	echo "[ERROR] This system is not support VxLAN (Failed, /sbin/modprobe vxlan)"
	exit 1
fi

read -p "Input Front-End Host's IP-Address: " front_ip
if [ -z ${front_ip} ]; then
	echo
	echo "[ERROR] Front-End Host's IP-Address is NULL"
	exit 1
fi

read -p "Input all physical hosts's common [root] password: " host_root_pw
if [ -z ${host_root_pw} ]; then
	echo
	echo "[ERROR] All host's [root] password is NULL"
	exit 1
fi

read -p "Input MySQL [root] password (default: passw0rd): " mysql_root_pw
mysql_root_pw=${mysql_root_pw:-passw0rd}

read -p "Input EYWA VM's [root] password (default: passw0rd): " vm_root_pw
vm_root_pw=${vm_root_pw:-passw0rd}

read -p "Input EYWA VM's [root] SSH Public Key File (default: ${ONE_VAR}/.ssh/id_rsa.pub): " vm_root_key_file
vm_root_key_file=${vm_root_key_file:-/var/lib/one/.ssh/id_rsa.pub}
vm_root_key="$(cat ${vm_root_key_file})"

oneadmin_pw=$(cat /var/lib/one/.one/one_auth | cut -d: -f2)
if [ -z ${oneadmin_pw} ]; then
	echo
	echo "[ERROR] oneadmin's password is NULL"
	exit 1
fi

read -p "Input Current ONE's Public Network Name (in 'Virtual Networks' list): " one_public_net
if [ -z ${one_public_net} ]; then
	echo
	echo "[ERROR] Public Network Name is NULL"
	exit 1
fi

read -p "Input NIC name of private network for VxLAN (default: eth0): " private_nic
private_nic=${private_nic:-eth0}

echo "--------------------------------------------"
echo "[Your Input Values....]"
echo " * Front-End Node's IP: ${front_ip}"
echo " * Physical Host's root password: ${host_root_pw}"
echo " * MySQL root password: ${mysql_root_pw}"
echo " * EYWA VM's root password: ${vm_root_pw}"
echo " * EYWA VM's SSH Public Key File: ${vm_root_key_file}"
echo " * EYWA Public Network Name: ${one_public_net}"
echo " * Private NIC for VxLAN: ${private_nic}"
echo "--------------------------------------------"
read -p "Confirm ? (y/n): " is_confirm

if [ ${is_confirm} != "y" ] && [ ${is_confirm} != "y" ]; then
	exit 1
fi

#------------------------------------------------------

echo
echo "[LOG] Starting........."

export DEBIAN_FRONTEND=noninteractive

apt-get -q update >/dev/null
apt-get -q -y install mysql-server libxml2-utils xmlstarlet sshpass

sed -i 's/^bind-address/#bind-address/g' /etc/mysql/my.cnf
mysqladmin -uroot password ${mysql_root_pw} 2> /dev/null
service mysql restart

ONE_HOST_LIST=$(su -l oneadmin -c "onehost list -x" | xmlstarlet sel -T -t -m //HOST_POOL/HOST/NAME -v . -n -)

SCRIPT_CHK_NET="${ONE_VAR}/remotes/vmm/check_eywa_net.sh"
SCRIPT_KVM_DEPLOY="${ONE_VAR}/remotes/vmm/kvm/deploy"
cp src/check_eywa_net.sh ${SCRIPT_CHK_NET}
chmod 755 ${SCRIPT_CHK_NET}
chown oneadmin:oneadmin ${SCRIPT_CHK_NET}
sed -i '/^data/i source $(dirname $0)/../check_eywa_net.sh' ${SCRIPT_KVM_DEPLOY}

if test ! -d ${ONE_LOG}/templates/; then
	mkdir -p ${ONE_LOG}/templates/ 2>/dev/null
	chown -R oneadmin:oneadmin ${ONE_LOG}/templates/
fi

#sed -i 's|type.*= "kvm"|type = "qemu"|g' /etc/one/oned.conf
sed -i "/RESTRICTED_ATTR/ s/^/#/" /etc/one/oned.conf
if ! grep -q "EYWA Config" ${ONE_CONF}; then
	cat src/add-oned.conf >> ${ONE_CONF}
fi
service opennebula restart

if test ! -f /usr/local/src/EYWA-Ubuntu-14.04_64.qcow2.gz; then
	wget 'https://onedrive.live.com/download?resid=28f8f701dc29e4b9%2110226' -O /usr/local/src/EYWA-Ubuntu-14.04_64.qcow2.gz
fi

oneimage create \
--name "EYWA-Ubuntu-14.04_64" \
--path "/usr/local/src/EYWA-Ubuntu-14.04_64.qcow2.gz" \
--driver qcow2 \
--prefix sd \
--datastore default

if test ! -f /usr/local/src/eywa_schema.sql.gz; then
	wget 'https://onedrive.live.com/download?resid=28f8f701dc29e4b9%2110238' -O /usr/local/src/eywa_schema.sql.gz
fi

mysql -uroot -p${mysql_root_pw} -e "CREATE DATABASE eywa"
mysql -uroot -p${mysql_root_pw} -e "GRANT ALL PRIVILEGES ON eywa.* TO 'eywa'@'localhost' IDENTIFIED BY '${oneadmin_pw}'"
mysql -uroot -p${mysql_root_pw} -e "GRANT ALL PRIVILEGES ON eywa.* TO 'eywa'@'%' IDENTIFIED BY '${oneadmin_pw}'"

echo "[LOG] Creating DB Schema........"
zcat /usr/local/src/eywa_schema.sql.gz | mysql -uroot -p${mysql_root_pw} eywa

if test ! -d ${ONE_VAR}/remotes/hooks/eywa; then
	cp -a src/eywa-remotes ${ONE_VAR}/remotes/hooks/eywa
	chown -R oneadmin:oneadmin ${ONE_VAR}/remotes/hooks/eywa
	chmod 0755 ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__ONE_VAR__@@|${ONE_VAR}|g" ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__VM_ROOT_PW__@@|${vm_root_pw}|g" ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__SSH_PUB_KEY__@@|${vm_root_key}|g" ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__FRONT_IP__@@|${front_ip}|g" ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__ONEADMIN_PW__@@|${oneadmin_pw}|g" ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__PUBLIC_NET__@@|${one_public_net}|g" ${ONE_VAR}/remotes/hooks/eywa/*
	sed -i "s|@@__PRIVATE_NIC__@@|${private_nic}|g" ${ONE_VAR}/remotes/hooks/eywa/*
fi

if [ ! -d ${ONE_VAR}/files/eywa-vr ] || [ ! -d ${ONE_VAR}/files/eywa-vm ]; then
	rm -rf ${ONE_VAR}/files/eywa-vr 2>/dev/null
	rm -rf ${ONE_VAR}/files/eywa-vm 2>/dev/null
	mkdir -p ${ONE_VAR}/files/eywa-*
	cp -a src/eywa-files/eywa-vr ${ONE_VAR}/files/
	cp -a src/eywa-files/eywa-vm ${ONE_VAR}/files/
	chown oneadmin:oneadmin ${ONE_VAR}/files
	chown -R oneadmin:oneadmin ${ONE_VAR}/files/eywa-vr ${ONE_VAR}/files/eywa-vm
    chmod -R 755 ${ONE_VAR}/files/eywa-vr ${ONE_VAR}/files/eywa-vm
fi

su -l oneadmin -c "onehost sync -f"

for target in ${ONE_HOST_LIST}
do
	ssh_command="sshpass -p'${host_root_pw}' ssh -o StrictHostKeyChecking=no root@${target}"
	${ssh_command} "apt-get -q update >/dev/null && apt-get -q -y install arptables"
	${ssh_command} "echo 'oneadmin    ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"
	${ssh_command} "echo 'Defaults env_keep -= \"HOME\"' >> /etc/sudoers"
done

while ! $(oneimage list | grep EYWA-Ubuntu | grep -q rdya); do echo; echo "[Notice] 'EYWA-Ubuntu-14.04_64' image is not ready.... please wait..."; su -l oneadmin -c 'oneimage list'; sleep 5; done
