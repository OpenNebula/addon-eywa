#!/bin/bash

DB_HOST="@@__FRONT_IP__@@"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="@@__ONEADMIN_PW__@@"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
T64=$1
XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $T64"

ONE_VM_ID=`$XPATH /VM/ID`
ONE_UID=`$XPATH /VM/TEMPLATE/CONTEXT/ONE_UID`
ONE_GID=`$XPATH /VM/GID`
ONE_HID=`$XPATH /VM/HISTORY_RECORDS/HISTORY/HID`
ONE_ETH0_IP=`$XPATH /VM/TEMPLATE/NIC/IP`
ONE_IS_EYWA=`$XPATH /VM/TEMPLATE/CONTEXT/IS_EYWA`
ONE_IS_VR=`$XPATH /VM/TEMPLATE/CONTEXT/IS_VR`
if [ "$ONE_IS_VR" == "yes" ]; then
	DB_IS_VR="1"
else
	DB_IS_VR="0"
fi

ONE_PASSWD=`$XPATH /VM/TEMPLATE/CONTEXT/PASSWD`
ONE_SSH_PUBLIC_KEY=`$XPATH /VM/TEMPLATE/CONTEXT/SSH_PUBLIC_KEY`

VR_PRI_IP="10.0.0.1"

QUERY_MC_ADDRESS=`$MYSQL_EYWA -e "select num,address from mc_address where uid='$ONE_UID'"`
VXLAN_G_N=`echo $QUERY_MC_ADDRESS | awk '{print $1}'` # VXLAN Group Number
VXLAN_G_A=`echo $QUERY_MC_ADDRESS | awk '{print $2}'` # VXLAN Group Address
$MYSQL_EYWA -e "update mc_address set uid='$ONE_UID' where num='$VXLAN_G_N'"
$MYSQL_EYWA -e "insert into vm_info values ('','$DB_IS_VR','$ONE_VM_ID','$ONE_UID','$ONE_HID','$ONE_ETH0_IP','0')"

##  또한, 계정의 VM에 사용할 비번, SSH가 계정의 Attibute에 각각 PASSWD="", SSH_PUBLIC_KEY=""로 지정되어 있지 않으면 VM생성이 취소 되어야 하는데, 아직....
## =============================================================================

if [ "$ONE_IS_EYWA" == "yes" ]; then
	if [ "$ONE_IS_VR" == "yes" ]; then
		## 추가 대상이 VR 일경우, 2가지 arptables 정책 모두 설정 (non-orphan)
		QUERY_EXIST_EYWA_VMs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='0' and uid='$ONE_UID' and hid='$ONE_HID' and vid!='$ONE_VM_ID' and deleted='0'"`
		EXIST_EYWA_VMs=`echo $QUERY_EXIST_EYWA_VMs | awk '{print $1}'`
		if [ $EXIST_EYWA_VMs -eq 0 ]; then
			## BR, VLXAN 장치 추가
			sudo brctl addbr VSi$VXLAN_G_N
			sudo brctl stp VSi$VXLAN_G_N off
			sudo brctl setfd VSi$VXLAN_G_N 0
			sudo ip link add vxlan$VXLAN_G_N type vxlan id $VXLAN_G_N group $VXLAN_G_A ttl 10 dev @@__PRIVATE_NIC__@@
			sudo ip link set up dev vxlan$VXLAN_G_N
			sudo brctl addif VSi$VXLAN_G_N vxlan$VXLAN_G_N
			sudo ifconfig VSi$VXLAN_G_N up
		fi
	else
		## 추가 대상이 VR이 아닌, 하위 EYWA VM일 경우, 2가지 arptables 정책만 추가 (orphan)
		## (정책 count검사를 위한 while 구문이 있었으나, 삭제 했음..)
		QUERY_EXIST_EYWA_VRs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='1' and uid='$ONE_UID' and hid='$ONE_HID' and deleted='0'"`
		EXIST_EYWA_VRs=`echo $QUERY_EXIST_EYWA_VRs | awk '{print $1}'`
		QUERY_EXIST_EYWA_VMs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='0' and uid='$ONE_UID' and hid='$ONE_HID' and vid!='$ONE_VM_ID' and deleted='0'"`
		EXIST_EYWA_VMs=`echo $QUERY_EXIST_EYWA_VMs | awk '{print $1}'`
		if [ $EXIST_EYWA_VRs -eq 0 ]; then
			## 대상 HOST에 동일 계정의 VR이 존재치 않을 경우,
			if [ $EXIST_EYWA_VMs -eq 0 ]; then
				## BR, VLXAN 장치 추가
				sudo brctl addbr VSi$VXLAN_G_N
				sudo brctl stp VSi$VXLAN_G_N off
				sudo brctl setfd VSi$VXLAN_G_N 0
				sudo ip link add vxlan$VXLAN_G_N type vxlan id $VXLAN_G_N group $VXLAN_G_A ttl 10 dev @@__PRIVATE_NIC__@@
				sudo ip link set up dev vxlan$VXLAN_G_N
				sudo brctl addif VSi$VXLAN_G_N vxlan$VXLAN_G_N
				sudo ifconfig VSi$VXLAN_G_N up
			fi
		else
			## 대상 HOST에 동일 계정의 VR이 존재할 경우, 
			if [ $EXIST_EYWA_VMs -eq 0 ]; then
				## 대상 HOST에 동일 계정의 VM이 존재치 않을 경우,
				## (VM이 전혀 없이 VR혼자만 노드에 있는 특수한 경우... 일단 무작업으로 Case는 유지..)
				echo "Pass...."
			else
				## 대상 HOST에 동일 계정의 VM이 존재할 경우,
				## (역시, 기존의 arptables 정책이나, BR설정을 변경할 요소가 없음. VM만 단순 추가 처리...)
				echo "Pass...."
			fi
		fi
	fi
fi

exit 0
