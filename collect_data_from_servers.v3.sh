#!/bin/bash
# Script to collect the status of lshw output from home servers
# Dependencies:
# * Open SSH: http://www.openssh.com/portable.html
# * LSHW: http://ezix.org/project/wiki/HardwareLiSter
# * JQ: http://stedolan.github.io/jq/
# * timeout: https://www.gnu.org/software/coreutils/
#
# On each machine you can run something like this from cron (Don't know CRON, no worries: https://crontab-generator.org/)
# 0 0 * * * /usr/sbin/lshw -json -quiet > /var/log/lshw-dump.json
# Author: Jose Vicente Nunez
#
set -o errtrace # Enable the err trap, code will get called when an error is detected
trap "echo ERROR: There was an error in ${FUNCNAME-main context}, details to follow" ERR

declare dependencies=(
    /usr/bin/timeout
    /usr/bin/ssh
    /usr/bin/lshw
    usr/bin/jq
)
for dependency in $dependencies; do
    test ! -x && echo "ERROR: Missing $dependency" && exit 100
done

declare -a servers=(
macmini2
mac-pro-1-1
dmaf5
)

function remote_copy {
    local server=$1
    echo "Visiting: $server"
    /usr/bin/timeout --kill-after 25.0s 20.0s \
        /usr/bin/scp \
            -o BatchMode=yes \
            -o logLevel=Error \
            -o ConnectTimeout=5 \
            -o ConnectionAttempts=3 \
            ${server}:/var/log/lshw-dump.json ${DATADIR}/lshw-$server-dump.json
    return $?
}

DATADIR="$HOME/Documents/lshw-dump"
if [ ! -d "$DATADIR" ]; then
    /usr/bin/mkdir -p -v "$DATADIR"|| "FATAL: Failed to create $DATADIR" && exit 100
fi
declare -A server_pid
for server in ${servers[*]}; do
    remote_copy $server &
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
    /usr/bin/jq '.["product","vendor", "configuration"]' $lshw|| echo "ERROR parsing '$lshw'" && exit 100
done
