#!/bin/bash

cd /var/lib/one/remotes/hooks

DB_HOST="@@__FRONT_IP__@@"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="@@__ONEADMIN_PW__@@"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
MYSQL_ONE="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST opennebula"
T64=$1
#XPATH="/var/lib/one/remotes/datastore/xpath.rb -b $T64"
XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $T64"

ONE_UID=`$XPATH /USER/ID`

#onevm delete "$ONE_UID-EYWA-Router"
#for vid in `$MYSQL_EYWA -e "select vid from vm_info where uid='$ONE_UID'" | sed -e '/vid/d'`
for vid in `$MYSQL_EYWA -e "select vid from vm_info where uid='$ONE_UID'"`
do
	onevm delete $vid
done
onevnet delete "$ONE_UID-Private-Net"
onetemplate delete "$ONE_UID-EYWA-Router"
onetemplate delete "$ONE_UID-Ubuntu(EYWA)"
#onetemplate delete "$ONE_UID-Ubuntu(Public)"
#for oid in `$MYSQL_ONE -e"select oid from template_pool where uid='$ONE_UID'" | sed -e '/oid/d'`
for oid in `$MYSQL_ONE -e"select oid from template_pool where uid='$ONE_UID'"`
do
	onetemplate delete $oid
done

$MYSQL_EYWA -e "update mc_address set uid='' where uid='$ONE_UID'"
