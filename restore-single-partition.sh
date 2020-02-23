#!/bin/bash
# License; Apache-2
# anddisa@gmail.com 2019/12

if [[ $# -ne 2 ]]; then
	echo "usage: restore-single-partition.sh <path to image> <partition name>"
	exit 0;
fi

curr_dir="$(dirname "$0")"
. "$curr_dir/functions.sh"

set -e   # fail early

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

pushBusybox

PARTITIONS=$* 
echo $PARTITIONS

stopRuntime 

echo "Restoring partition image ..."
PARTITION="/dev/block/by-name/$2"
echo "writing $1 to $PARTITION ..."
if [[ "$1" == "*.gz" ]]
then
	zcat $1 2>/dev/null | pv -trab | $AS "/dev/busybox dd of=$PARTITION 2>/dev/null"
else
	cat $1 2>/dev/null | pv -trab | $AS "/dev/busybox dd of=$PARTITION 2>/dev/null"
fi

cleanup

startRuntime

