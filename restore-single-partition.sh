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
trap cleanup EXIT

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
PV_CMD="pv -trab"
rl_flag=$(getRateLimitPvFlag)
[[ -n "$rl_flag" ]] && PV_CMD="pv -trab $rl_flag"

if [[ "$1" == *.gz ]]
then
    zcat "$1" 2>/dev/null | $PV_CMD | $AS "$BB dd of=$PARTITION 2>/dev/null"
else
    cat "$1" 2>/dev/null | $PV_CMD | $AS "$BB dd of=$PARTITION 2>/dev/null"
fi

cleanup

startRuntime

