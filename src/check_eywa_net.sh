#!/bin/bash

EYWA_VID=`grep "one-[0-9]" $domain | sed -e 's/<name>//g' | sed -e 's/<\/name>//g' | cut -d- -f2`
TMP_FILE=`mktemp`
trap "rm -f $TMP_FILE" EXIT
CONTEXT_FILE="/var/lib/one/vms/${EYWA_VID}/context.sh"
su -l oneadmin -c "ssh -l oneadmin @@__FRONT_IP__@@ 'cat $CONTEXT_FILE'" > $TMP_FILE

source $TMP_FILE

if [ ${IS_EYWA} == "yes" ]; then
    DB_HOST="@@__FRONT_IP__@@"
    DB_NAME="eywa"
    DB_USER="eywa"
    DB_PASS="@@__ONEADMIN_PW__@@"
    MYSQL_EYWA="mysql -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME -s -N"
    
    while true
    do
    	EYWA_UID=`$MYSQL_EYWA -e "select uid from vm_info where vid='$EYWA_VID'"`
    	if [ "x$EYWA_UID" != "x" ]; then
    		break
    	fi
    	sleep 1
    done
    EYWA_NUM=`$MYSQL_EYWA -e "select num from mc_address where uid='$EYWA_UID'"`
    
    while ! $(ifconfig VSi${EYWA_NUM} >/dev/null 2>/dev/null)
    do
    	sleep 1
    done
fi
