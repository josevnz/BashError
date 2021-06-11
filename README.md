# Bash error handling

On this article 

## A simple script that downloads a hardware report from multiple hosts and inserts it into a database. What could go wrong? :-)

Say that you have a little cron job on each one of your Linux HOME machines, and [you have a script to collect](https://github.com/josevnz/BashError/blob/main/collect_data_from_servers.sh) the hardware information from each:

```shell=
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
declare -a servers=(
dmaf5
)

DATADIR="$HOME/Documents/lshw-dump"

/usr/bin/mkdir -p -v "$DATADIR"
for server in ${servers[*]}; do
    echo "Visiting: $server"
    /usr/bin/scp -o logLevel=Error ${server}:/var/log/lshw-dump.json ${DATADIR}/lshw-$server-dump.json &
done
wait
for lshw in $(/usr/bin/find $DATADIR -type f -name 'lshw-*-dump.json'); do
    /usr/bin/jq '.["product","vendor", "configuration"]' $lshw
done
```

If everything goes well then you collect your files, in parallel (as you don't have more than 10 machines you can afford to ssh to all of them at the same time, right) and then show the hardware details of each one (you are so proud of your babies :-)):

```
Visiting: dmaf5
lshw-dump.json                                                                                         100%   54KB 136.9MB/s   00:00    
"DMAF5 (Default string)"
"BESSTAR TECH LIMITED"
{
  "boot": "normal",
  "chassis": "desktop",
  "family": "Default string",
  "sku": "Default string",
  "uuid": "00020003-0004-0005-0006-000700080009"
}
```

But life is not perfect. Bad things happen:
* Your report didn't run because the server was down
* You could not create the directory where the files need to be saved
* The tools you need to run the script are missing
* You cannot collect the report because your remote machine crashed (too much Dog Coin mining ;-)
* One or more of the reports you just got is corrupt. 
* And the list of unexpected things that can go wrong goes on and on...

Current version of the script has a problem: It will run from the begining to the end, errors or not:

```shell=
./collect_data_from_servers.sh 
Visiting: macmini2
Visiting: mac-pro-1-1
Visiting: dmaf5
lshw-dump.json                                                                                         100%   54KB  48.8MB/s   00:00    
scp: /var/log/lshw-dump.json: No such file or directory
scp: /var/log/lshw-dump.json: No such file or directory
parse error: Expected separator between values at line 3, column 9

```

Keep reading, I'll show you a few things to make your script more robust and in some times recover from failure.

# The nuclear option: Failing hard, failing fast

The proper way to handle errors is to check if the program finished successfully or not. Yeah, sounds obvious but return code (an integer number stored in bash $? or $! variable) have sometimes a broader meaning. ([Bash man page](https://man7.org/linux/man-pages/man1/bash.1.html)) tell us something:

> For the shell's purposes, a command which exits with a zero exit
       status has succeeded.  An exit status of zero indicates success.
       A non-zero exit status indicates failure.  When a command
       terminates on a fatal signal N, bash uses the value of 128+N as
       the exit status.

As usual, you should always read the man page of the scripts you are calling, to see what are the conventions. If you have programmed with a language like Java or Python then you are most likely familiar with with exceptions and their different meanings (and how not all them are handled the same way).

If you add ```set -o errexit``` to your script, from that point forward it will abort the execution if any command exists with a code != 0. But errexit isn’t used when executing functions inside an if condition, so instead of remembering that little gotcha I rather do explict error handling.

So let's take a look a [V2 of the script](https://github.com/josevnz/BashError/blob/main/collect_data_from_servers.v2.sh). It is slightly better:

```shell=
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
    /usr/bin/jq '.["product","vendor", "configuration"]' $lshw|| echo "ERROR parsing '$lshw'" && exit 100
done

```

I did a few things:

1. Lines 11,12 I enable error trace and added a 'trap' to tell the user there was an error and there is turbulence ahead. You may want to kill your script here instead, I'll show you why that may not be the best
2. Line 20, if the directory doesn't exist then try to create it on line 21. If directory creation fails the exit with an error
3. On line 27, after running each background job, I capture the PID and associate that with the machine (1:1 relationship).
4. On lines 33-35 I wait for the scp task to finish, get the return code and if is an error abort
5. On line 37 I check than the file could be parsed, otherwise I exit with an error

So how does the error handling looks now?
```shell=
Visiting: macmini2
Visiting: mac-pro-1-1
Visiting: dmaf5
lshw-dump.json                                                                                         100%   54KB 146.1MB/s   00:00    
scp: /var/log/lshw-dump.json: No such file or directory
ERROR: There was an error in main context, details to follow
ERROR: Copy from mac-pro-1-1 had problems, will not continue
scp: /var/log/lshw-dump.json: No such file or directory

```

As you can see this version is better at detecting errors but it is very unforgiving. Also it doesn't detect all the errors, does it?

## When you get stuck and you wish you had an alarm

## Waiting for the end of the world (how and when to retry)


## If I fail, do I have to do this all over again? Using a checkpoint

## Leaving crumbs behind: What to log, how to log, verbose output


