#!/bin/bash

VM_ID=$1
TEMPLATE=$2
SAVE_DIR="@@__ONE_VAR__@@/vms/$VM_ID"

#XPATH="/var/tmp/one/hooks/eywa/xpath.rb -b $TEMPLATE"
#$XPATH > $SAVE_DIR/TEMPLATE.xpath

echo $TEMPLATE > $SAVE_DIR/TEMPLATE.base64
echo $TEMPLATE | base64 --decode > $SAVE_DIR/TEMPLATE
