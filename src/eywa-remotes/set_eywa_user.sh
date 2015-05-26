#!/bin/bash

cd /var/lib/one/remotes/hooks/eywa

DB_HOST="@@__FRONT_IP__@@"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="@@__ONEADMIN_PW__@@"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
DATE=`date +%Y-%m-%d_%H_%M`
T64=$1
XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $T64"

## Metadata
ONE_UID=`$XPATH /USER/ID`
ONE_GID=`$XPATH /USER/GID`
ONE_UNAME=`$XPATH /USER/NAME`
ONE_GNAME=`$XPATH /USER/GNAME`

#QUERY_MC_ADDRESS=($($MYSQL_EYWA -e "select num,address from mc_address where uid='' order by rand() limit 1"))
#QUERY_MC_ADDRESS=($($MYSQL_EYWA -e "select num,address from mc_address where uid is null order by rand() limit 1"))
QUERY_MC_ADDRESS=($($MYSQL_EYWA -e "select num,address from mc_address where uid is null or uid='' limit 1"))
VXLAN_G_N=${QUERY_MC_ADDRESS[0]} # VXLAN Group Number
VXLAN_G_A=${QUERY_MC_ADDRESS[1]} # VXLAN Group Address

$MYSQL_EYWA -e "update mc_address set uid='$ONE_UID' where num='$VXLAN_G_N'"

## Create EYWA Private Network
TMPL="eywa_private_net.tmpl"
TMP="$ONE_UID-$TMPL.$$.$DATE"
sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL | sed -e "s/@@__BR__@@/$VXLAN_G_N/g" > $TMP
onevnet create $TMP
onevnet chmod "$ONE_UID-Private-Net" 644
mv $TMP /var/log/one/templates/

## Create EYWA Private-VM Template
TMPL="eywa_private_vm.tmpl"
TMP="$ONE_UID-$TMPL.$$.$DATE"
sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL >> $TMP
TMPL_ID=`onetemplate create $TMP | awk '{print $NF}'`
onetemplate chmod $TMPL_ID 600
onetemplate chown $TMPL_ID $ONE_UID $ONE_GID
mv $TMP /var/log/one/templates/

## Create Public-VM Template (None EYWA)
#TMPL="public_vm.tmpl"
#TMP="$ONE_UID-$TMPL.$$.$DATE"
#sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL >> $TMP
#TMPL_ID=`onetemplate create $TMP | awk '{print $NF}'`
#onetemplate chmod $TMPL_ID 600
#onetemplate chown $TMPL_ID $ONE_UID $ONE_GID
#mv $TMP /var/log/one/templates/

## Create EYWA VR(Vritual Router) Template (Owner: oneadmin)
TMPL="eywa_virtual_router.tmpl"
TMP="$ONE_UID-$TMPL.$$.$DATE"
sed -e "s/@@__UID__@@/$ONE_UID/g" $TMPL > $TMP
TMPL_ID=`onetemplate create $TMP | awk '{print $NF}'`
onetemplate instantiate $TMPL_ID
mv $TMP /var/log/one/templates/

