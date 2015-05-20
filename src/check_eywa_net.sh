#!/bin/bash

DB_HOST="192.168.33.10"
DB_NAME="eywa"
DB_USER="eywa"
DB_PASS="1234"
MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"

EYWA_VID=`grep "one-[0-9]" $domain | sed -e 's/<name>//g' | sed -e 's/<\/name>//g' | cut -d- -f2`
echo $EYWA_VID > /tmp/111

EYWA_UID=`$MYSQL_EYWA -e "select uid from vm_info where vid='$EYWA_VID'"`
EYWA_NUM=`$MYSQL_EYWA -e "select num from mc_address where uid='$EYWA_UID'"`

while ! $(ifconfig VSi${EYWA_NUM} >/dev/null 2>/dev/null)
do
	sleep 5
done
