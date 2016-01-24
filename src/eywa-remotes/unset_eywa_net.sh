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

EXIST_EYWA_VRs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='1' and uid='$ONE_UID' and vid!='$ONE_VM_ID' and hid='$ONE_HID' and deleted='0'"`
EXIST_EYWA_VMs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='0' and uid='$ONE_UID' and vid!='$ONE_VM_ID' and hid='$ONE_HID' and deleted='0'"`

#--------------------------------------------------------------------------------------------

function undeploy_network() {
	sudo ip link set down dev VSi$VXLAN_G_N
	sudo brctl delif VSi$VXLAN_G_N vxlan$VXLAN_G_N
	sudo ip link delete vxlan$VXLAN_G_N
	sudo brctl delbr VSi$VXLAN_G_N
}

#--------------------------------------------------------------------------------------------

## Delete ARP Policy
if [ "$ONE_IS_VR" == "yes" ] && [ $EXIST_EYWA_VRs -eq 0 ]; then
	### (1)
	sudo arptables -D FORWARD -j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1
	### (2)
	sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
fi

## Undeploy aprtables and network...
if [ $EXIST_EYWA_VRs -eq 0 ] && [ $EXIST_EYWA_VMs -eq 0 ]; then
	undeploy_network
fi

$MYSQL_EYWA -e "update vm_info set deleted='1' where vid='$ONE_VM_ID'"
