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

declare REMOTE_FILE="/var/log/lshw-dump.json"
declare MAX_RETRIES=3

declare -a dependencies=(/usr/bin/timeout /usr/bin/ssh /usr/bin/jq)
for dependency in ${dependencies[@]}; do
    if [ ! -x $dependency ]; then
        echo "ERROR: Missing $dependency"
        exit 100
    fi
done

declare -a servers=(
macmini2
mac-pro-1-1
dmaf5
)

function remote_copy {
    local server=$1
    local retries=$2
    local now=1
    status=0
    while [ $now -le $retries ]; do
        echo "INFO: Trying to copy file from: $server, attempt=$now"
        /usr/bin/timeout --kill-after 25.0s 20.0s \
            /usr/bin/scp \
                -o BatchMode=yes \
                -o logLevel=Error \
                -o ConnectTimeout=5 \
                -o ConnectionAttempts=3 \
                ${server}:$REMOTE_FILE ${DATADIR}/lshw-$server-dump.json
        status=$?
        if [ $status -ne 0 ]; then
            sleep_time=$(((RANDOM % 60)+ 1))
            echo "WARNING: Copy failed for $server:$REMOTE_FILE. Waiting '${sleep_time} seconds' before re-trying..."
            /usr/bin/sleep ${sleep_time}s
        else
            break # All good, no point on waiting...
        fi
        ((now=now+1))
    done
    return $status
}

DATADIR="$HOME/Documents/lshw-dump"
if [ ! -d "$DATADIR" ]; then
    /usr/bin/mkdir -p -v "$DATADIR"|| "FATAL: Failed to create $DATADIR" && exit 100
fi
declare -A server_pid
for server in ${servers[*]}; do
    remote_copy $server $MAX_RETRIES &
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
