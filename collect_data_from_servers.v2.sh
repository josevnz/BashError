#!/bin/bash
# Script to collect the status of lshw output from home servers
# Dependencies:
# * LSHW: http://ezix.org/project/wiki/HardwareLiSter
# * JQ: http://stedolan.github.io/jq/
#
# On each machine you can run something like this from cron (Don't know CRON, no worries: https://crontab-generator.org/)
# 0 0 * * * /usr/sbin/lshw -json -quiet > /var/log/lshw-dump.json
# Author: Jose Vicente Nunez
#
set -o errtrace # Enable the err trap, code will get called when an error is detected
trap "echo ERROR: There was an error in ${FUNCNAME-main context}, details to follow" ERR
declare -a servers=(
macmini2
mac-pro-1-1
dmaf5
)

DATADIR="$HOME/Documents/lshw-dump"
if [ ! -d "$DATADIR" ]; then
    /usr/bin/mkdir -p -v "$DATADIR"|| "FATAL: Failed to create $DATADIR" && exit 100
fi
declare -A server_pid
for server in ${servers[*]}; do
    echo "Visiting: $server"
    /usr/bin/scp -o logLevel=Error ${server}:/var/log/lshw-dump.json ${DATADIR}/lshw-$server-dump.json &
    server_pid[$server]=$! # Save the PID of the scp  of a given server for later
done
# Iterate through all the servers and:
# Wait for the return code of each
# Check the exit code from each scp
for server in ${!server_pid[*]}; do
    wait ${server_pid[$server]}
    test $? -ne 0 && echo "ERROR: Copy from $server had problems, will not continue" && exit 100
done
for lshw in $(/usr/bin/find $DATADIR -type f -name 'lshw-*-dump.json'); do
    /usr/bin/jq '.["product","vendor", "configuration"]' $lshw
done
