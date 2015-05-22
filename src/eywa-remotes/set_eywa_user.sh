#!/bin/bash

cd @@__ONE_VAR__@@/remotes/hooks/eywa

DB_HOST="@@__FRONT_IP__@@"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="@@__ONEADMIN_PW__@@"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
DATE=`date +%Y-%m-%d_%H_%M`
T64=$1
#XPATH="@@__ONE_VAR__@@/remotes/datastore/xpath.rb -b $T64"
XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $T64"

## 메타정보 수집
ONE_UID=`$XPATH /USER/ID`
ONE_GID=`$XPATH /USER/GID`
ONE_UNAME=`$XPATH /USER/NAME`
ONE_GNAME=`$XPATH /USER/GNAME`

#QUERY_MC_ADDRESS=`$MYSQL_EYWA -e "select num,address from mc_address where uid='' order by rand() limit 1"`
#QUERY_MC_ADDRESS=`$MYSQL_EYWA -e "select num,address from mc_address where uid is null order by rand() limit 1"`
QUERY_MC_ADDRESS=`$MYSQL_EYWA -e "select num,address from mc_address where uid is null or uid='' limit 1"`
VXLAN_G_N=`echo $QUERY_MC_ADDRESS | awk '{print $1}'` # VXLAN Group Number
VXLAN_G_A=`echo $QUERY_MC_ADDRESS | awk '{print $2}'` # VXLAN Group Address
$MYSQL_EYWA -e "update mc_address set uid='$ONE_UID' where num='$VXLAN_G_N'"

## EYWA 사설 네트워크 생성
TMPL="eywa_private_net.tmpl"
TMP="$ONE_UID-$TMPL.$$.$DATE"
sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL | sed -e "s/@@__BR__@@/$VXLAN_G_N/g" > $TMP
onevnet create $TMP
onevnet chmod "$ONE_UID-Private-Net" 644
mv $TMP /var/log/one/templates/

## EYWA VR(Vritual Router) 생성 (Owner: oneadmin)
TMPL="eywa_virtual_router.tmpl"
TMP="$ONE_UID-$TMPL.$$.$DATE"
sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL > $TMP
ONE_VM_ID=`onevm create $TMP | awk '{print $NF}'`
#onevm chmod $ONE_VM_ID 000
#onevm chown $ONE_VM_ID $ONE_UID $ONE_GID
#mv $TMP /var/log/one/templates/
## EYWA VR Template 등록
#TMPL="eywa_virtual_router.tmpl"
#TMP="$ONE_UID-$TMPL.$$.$DATE"
#sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL >> $TMP
TMPL_ID=`onetemplate create $TMP | awk '{print $NF}'`
mv $TMP /var/log/one/templates/

## EYWA VM 생성용도 Template 배포
TMPL="eywa_private_vm.tmpl"
TMP="$ONE_UID-$TMPL.$$.$DATE"
sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL >> $TMP
TMPL_ID=`onetemplate create $TMP | awk '{print $NF}'`
onetemplate chmod $TMPL_ID 600
onetemplate chown $TMPL_ID $ONE_UID $ONE_GID
mv $TMP /var/log/one/templates/

## Non-EYWA VM (Public VM) Template 배포
#TMPL="public_vm.tmpl"
#TMP="$ONE_UID-$TMPL.$$.$DATE"
#sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL >> $TMP
#TMPL_ID=`onetemplate create $TMP | awk '{print $NF}'`
#onetemplate chmod $TMPL_ID 600
#onetemplate chown $TMPL_ID $ONE_UID $ONE_GID
#mv $TMP /var/log/one/templates/

## Quota 적용
## ("oneuser defaultquota"로 일괄 적용 상태. User별 조정이 필요하면 주석 해제 및 적절히 수정)
#TMPLE="user_quota.tmp;"
#TMP="$ONE_UID-$TMPL.$$.$DATE"
#cp -a $TMPLE $TMP
#oneuser quota $ONE_UID $TMP
#mv $TMP /var/log/one/templates/

exit 0
