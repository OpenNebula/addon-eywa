#!/bin/bash

DB_HOST="@@__FRONT_IP__@@"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="@@__ONEADMIN_PW__@@"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
T64=$1
XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $T64"
SSH_oneadmin="ssh -l oneadmin @@__FRONT_IP__@@ -i /var/lib/one/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=5"

ONE_VM_ID=`$XPATH /VM/ID`
ONE_UID=`$XPATH /VM/TEMPLATE/CONTEXT/ONE_UID`
ONE_GID=`$XPATH /VM/GID`
ONE_HID=`$XPATH /VM/HISTORY_RECORDS/HISTORY/HID`
ONE_ETH0_IP=`$XPATH /VM/TEMPLATE/NIC/IP`
ONE_IS_EYWA=`$XPATH /VM/TEMPLATE/CONTEXT/IS_EYWA`
ONE_IS_VR=`$XPATH /VM/TEMPLATE/CONTEXT/IS_VR`
ONE_PASSWD=`$XPATH /VM/TEMPLATE/CONTEXT/PASSWD`
ONE_SSH_PUBLIC_KEY=`$XPATH /VM/TEMPLATE/CONTEXT/SSH_PUBLIC_KEY`
VR_PRI_IP="10.0.0.1"

QUERY_MC_ADDRESS=($($MYSQL_EYWA -e "select num,address from mc_address where uid='$ONE_UID'"))
VXLAN_G_N=${QUERY_MC_ADDRESS[0]} # VXLAN Group Number
VXLAN_G_A=${QUERY_MC_ADDRESS[1]} # VXLAN Group Address

if [ "$ONE_IS_EYWA" == "yes" ]; then
	if [ "$ONE_IS_VR" == "yes" ]; then DB_IS_VR="1"; else DB_IS_VR="0"; fi
	#$MYSQL_EYWA -e "update mc_address set uid='$ONE_UID' where num='$VXLAN_G_N'"
	$MYSQL_EYWA -e "insert into vm_info values ('','$DB_IS_VR','$ONE_VM_ID','$ONE_UID','$ONE_HID','$ONE_ETH0_IP','0')"
fi

EXIST_EYWA_VRs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='1' and uid='$ONE_UID' and vid!='$ONE_VM_ID' and hid='$ONE_HID' and deleted='0'"`
EXIST_EYWA_VMs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='0' and uid='$ONE_UID' and vid!='$ONE_VM_ID' and hid='$ONE_HID' and deleted='0'"`

#--------------------------------------------------------------------------------------------

function deploy_network() {
	sudo brctl addbr VSi$VXLAN_G_N
	sudo brctl stp VSi$VXLAN_G_N off
	sudo brctl setfd VSi$VXLAN_G_N 0
	sudo ip link add vxlan$VXLAN_G_N type vxlan id $VXLAN_G_N group $VXLAN_G_A ttl 10 dev @@__PRIVATE_NIC__@@
	sudo ip link set vxlan$VXLAN_G_N mtu 1500
	sudo ip link set up dev vxlan$VXLAN_G_N
	sudo brctl addif VSi$VXLAN_G_N vxlan$VXLAN_G_N
	sudo ifconfig VSi$VXLAN_G_N up
}

#--------------------------------------------------------------------------------------------

## Prevent duplicate VR in same host...
if [ "$ONE_IS_VR" == "yes" ] && [ $EXIST_EYWA_VRs -ne 0 ]; then
		$SSH_oneadmin "onevm delete $ONE_VM_ID"
		exit 128
fi

#--------------------------------------------------------------------------------------------

## Deploy aprtables and network...
if [ $EXIST_EYWA_VRs -eq 0 ] && [ $EXIST_EYWA_VMs -eq 0 ]; then
	deploy_network
fi

## Create ARP Policy
if [ "$ONE_IS_VR" == "yes" ]; then
	sudo arptables -A FORWARD -j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1 ### ①
	sudo arptables -A FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1 ### ②
fi
