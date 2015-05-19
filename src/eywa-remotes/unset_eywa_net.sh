#!/bin/bash

DB_HOST="@@__FRONT_IP__@@"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="@@__ONEADMIN_PW__@@"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
T64=$1
XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $T64"

ONE_VM_ID=`$XPATH /VM/ID`
## 삭제 마킹 가장 우선... (추후, 트랜잭션이든, 다수 VM을 일괄 삭제에 대한 처리 필요...)
$MYSQL_EYWA -e "update vm_info set deleted='1' where vid='$ONE_VM_ID'"

ONE_UID=`$XPATH /VM/TEMPLATE/CONTEXT/ONE_UID`
ONE_GID=`$XPATH /VM/GID`
ONE_HID=`$XPATH /VM/HISTORY_RECORDS/HISTORY/HID`
ONE_ETH0_IP=`$XPATH /VM/TEMPLATE/CONTEXT/NIC/IP`

QUERY_MC_ADDRESS=`$MYSQL_EYWA -e "select num,address from mc_address where uid='$ONE_UID'"`
VXLAN_G_N=`echo $QUERY_MC_ADDRESS | awk '{print $1}'` # VXLAN Group Number
VXLAN_G_A=`echo $QUERY_MC_ADDRESS | awk '{print $2}'` # VXLAN Group Address

ONE_IS_EYWA=`$XPATH /VM/TEMPLATE/CONTEXT/IS_EYWA`
ONE_IS_VR=`$XPATH /VM/TEMPLATE/CONTEXT/IS_VR`
VR_PRI_IP="10.0.0.1"

#NETDEV_0=`sudo virsh dumpxml one-$ONE_VM_ID | xmlstarlet sel -t -v '/domain/devices/interface[alias/@name="net0"]/target/@dev'`
#NETDEV_1=`sudo virsh dumpxml one-$ONE_VM_ID | xmlstarlet sel -t -v '/domain/devices/interface[alias/@name="net1"]/target/@dev'`

## ==VR인지 아닌지에 따라 분기==
##   arptables 정책이 오작동에 의해 여러번 중복됨을 방지하고자
##   count검사가 필수라 while구문을 사용하였으나,
##   Prototype에서는 단순 추가/삭제로만 처리.. 추후 반영 필요...
##   (while구문의 count 검사 형태는 일단 주석 처리...)

if [ "$ONE_IS_EYWA" == "yes" ]; then
	if [ "$ONE_IS_VR" == "yes" ]; then
		## 삭제 대상이 VR 일경우, 2가지 arptables 정책 모두 삭제 (non-orphan)
		## (계정당,노드당 VR은 한개만 존재해야 하므로, 잔존 VR이 있는지 없는지는 조사할 필요가 없다)
		QUERY_EXIST_EYWA_VMs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='0' and uid='$ONE_UID' and hid='$ONE_HID' and vid!='$ONE_VM_ID' and deleted='0'"`
		EXIST_EYWA_VMs=`echo $QUERY_EXIST_EYWA_VMs | awk '{print $1}'`
		if [ $EXIST_EYWA_VMs -eq 0 ]; then
			## 대상 HOST에 동일 계정의 EYWA VM이 하나도 없으면, arptables 정책 모두 삭제
			## (현재 VR도 삭제되는 상황이므로 VR조사는 불필요)
			sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -s $VR_PRI_IP -d $VR_PRI_IP --opcode 2
			sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
			sudo arptables -D FORWARD -j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1
			## BR, VLXAN 장치 삭제
			sudo ifconfig VSi$VXLAN_G_N down
			sudo brctl delif VSi$VXLAN_G_N vxlan$VXLAN_G_N
			sudo ip link delete vxlan$VXLAN_G_N
			sudo brctl delbr VSi$VXLAN_G_N
		#	while [ `sudo arptables -vnL | grep -c "\-j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1"` -gt 0 ]; do
		#		sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
		#	done
		#	while [ `sudo arptables -vnL | grep -c "\-j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1"` -gt 0 ]; do
		#		sudo arptables -D FORWARD -j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1
		#	done
		else
			## 대상 HOST에 동일 EYWA VM이 하나 이상 남아 있을 때,
			## (VR만 삭제 되는 상황이므로, 나머지 EYWA VM들은 다른 노드의 VR을 이용할 수 있게 opphan모드로 arptable 조정)
			sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -s $VR_PRI_IP -d $VR_PRI_IP --opcode 2
			sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
		#	while [ `sudo arptables -vnL | grep -c "\-j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1"` -gt 0 ]; do
		#		sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
		#	done
		#	while [ `sudo arptables -vnL | grep -c "\-j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1"` -gt 1 ]; do
		#		sudo arptables -D FORWARD -j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1
		#	done
		fi
	else
		## 삭제 대상이 VR이 아닌, 하위 EYWA VM일 경우, 1가지 arptables 정책만 삭제 (orphan)
		## (정책 count검사를 위한 while 구문이 있었으나, 삭제 했음..)
		QUERY_EXIST_EYWA_VRs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='1' and uid='$ONE_UID' and hid='$ONE_HID' and deleted='0'"`
		EXIST_EYWA_VRs=`echo $QUERY_EXIST_EYWA_VRs | awk '{print $1}'`
		QUERY_EXIST_EYWA_VMs=`$MYSQL_EYWA -e "select count(*) from vm_info where is_vr='0' and uid='$ONE_UID' and hid='$ONE_HID' and vid!='$ONE_VM_ID' and deleted='0'"`
		EXIST_EYWA_VMs=`echo $QUERY_EXIST_EYWA_VMs | awk '{print $1}'`
		if [ $EXIST_EYWA_VRs -eq 0 ]; then
			## 대상 HOST에 동일 계정의 VR이 존재치 않을 경우,
			if [ $EXIST_EYWA_VMs -eq 0 ]; then
				## 대상 HOST에 동일 계정의 VM이 존재치 않을 경우,
				sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -s $VR_PRI_IP -d $VR_PRI_IP --opcode 2
				sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
				sudo arptables -D FORWARD -j DROP -i vxlan$VXLAN_G_N -o vnet+ -s $VR_PRI_IP --opcode 1
				## BR, VLXAN 장치 삭제
				sudo ifconfig VSi$VXLAN_G_N down
				sudo brctl delif VSi$VXLAN_G_N vxlan$VXLAN_G_N
				sudo ip link delete vxlan$VXLAN_G_N
				sudo brctl delbr VSi$VXLAN_G_N
			else
				## 대상 HOST에 동일 계정의 VM이 존재할 경우,
				sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -s $VR_PRI_IP -d $VR_PRI_IP --opcode 2
				sudo arptables -D FORWARD -j DROP -i vnet+ -o vxlan$VXLAN_G_N -d $VR_PRI_IP --opcode 1
			fi
		else
			## 대상 HOST에 동일 계정의 VR이 존재할 경우, 
			if [ $EXIST_EYWA_VMs -eq 0 ]; then
				## 대상 HOST에 동일 계정의 VM이 존재치 않을 경우,
				## (VM이 전혀 없이 VR혼자만 노드에 있는 특수한 경우... 일단 무작업으로 Case는 유지..)
				echo "Pass...."
			else
				## 대상 HOST에 동일 계정의 VM이 존재할 경우,
				## (역시, 기존의 arptables 정책이나, BR설정을 변경할 요소가 없음. VM만 단순 삭제 처리...)
				echo "Pass...."
			fi
		fi
	fi
fi

## 상단에 VM_ID확인 후, 바로 삭제 처리로 대체... (트랜잭션, 일관성 문제 있음... 고민 필요...)
#$MYSQL_EYWA -e "update vm_info set deleted='1' where vid='$ONE_VM_ID'"

exit 0
