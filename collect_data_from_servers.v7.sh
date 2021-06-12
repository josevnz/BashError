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

declare -a dependencies=(/usr/bin/timeout /usr/bin/ssh /usr/bin/jq)
for dependency in ${dependencies[@]}; do
    if [ ! -x $dependency ]; then
        echo "ERROR: Missing $dependency"
        exit 100
    fi
done

SCRIPT_NAME=$(/usr/bin/basename $BASH_SOURCE)|| exit 100
FULL_PATH=$(/usr/bin/realpath ${BASH_SOURCE[0]})|| exit 100
set -o errtrace # Enable the err trap, code will get called when an error is detected
trap "echo ERROR: There was an error in ${FUNCNAME[0]-main context}, details to follow" ERR
declare CACHE_DIR="/tmp/$SCRIPT_NAME/$YYYYMMDD"

function message {
    message="$1"
    func_name="${2-unknown}"
    priority=6
    if [ -z "$2" ]; then
        echo "INFO:" $message
    else
        echo "ERROR:" $message
        priority=0
    fi
    /usr/bin/logger --journald<<EOF
MESSAGE_ID=$SCRIPT_NAME
MESSAGE=$message
PRIORITY=$priority
CODE_FILE=$FULL_PATH
CODE_FUNC=$func_name
EOF
}

# Logic to clean up the cache dir on daily basis is not shown here
if [ ! -d "$CACHE_DIR" ]; then
    /usr/bin/mkdir -p -v "$CACHE_DIR"|| exit 100
fi
trap "/bin/rm -rf $CACHE_DIR" INT KILL

function check_previous_run {
    local machine=$1
    test -f $CACHE_DIR/$machine && return 0|| return 1
}

function mark_previous_run {
    machine=$1
    /usr/bin/touch $CACHE_DIR/$machine
    return $?
}

declare REMOTE_FILE="/var/log/lshw-dump.json"
declare MAX_RETRIES=3

declare -a servers=(
dmaf5
macmini2
mac-pro-1-1
)

function remote_copy {
    local server=$1
    check_previous_run $server
    test $? -eq 0 && message "$1 ran successfully before. Not doing again" && return 0
    local retries=$2
    local now=1
    status=0
    while [ $now -le $retries ]; do
        message "Trying to copy file from: $server, attempt=$now"
        /usr/bin/timeout --kill-after 25.0s 20.0s \
            /usr/bin/scp \
                -o BatchMode=yes \
                -o logLevel=Error \
                -o ConnectTimeout=5 \
                -o ConnectionAttempts=3 \
                ${server}:$REMOTE_FILE ${DATADIR}/lshw-$server-dump.json.$$
        status=$?
        if [ $status -ne 0 ]; then
            sleep_time=$(((RANDOM % 60)+ 1))
            message "Copy failed for $server:$REMOTE_FILE. Waiting '${sleep_time} seconds' before re-trying..." ${FUNCNAME[0]}
            /usr/bin/sleep ${sleep_time}s
        else
            break # All good, no point on waiting...
        fi
        ((now=now+1))
    done
    if [ $status -eq 0 ]; then
        /usr/bin/jq '.' ${DATADIR}/lshw-$server-dump.json.$$ > /dev/null 2>&1
        status=$?
        if [ $status -eq 0 ]; then
            /usr/bin/mv -v -f ${DATADIR}/lshw-$server-dump.json.$$ ${DATADIR}/lshw-$server-dump.json && mark_previous_run $server
            test $? -ne 0 && status=1
        else
            message "${DATADIR}/lshw-$server-dump.json.$$ Is corrupted. Leaving for inspection..." ${FUNCNAME[0]}
        fi
    fi
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
    test $? -ne 0 && message "Copy from $server had problems, will not continue" main && exit 100
done
for lshw in $(/usr/bin/find $DATADIR -type f -name 'lshw-*-dump.json'); do
    /usr/bin/jq '.["product","vendor", "configuration"]' $lshw
done
