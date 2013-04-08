#!/bin/bash

# XXX: TODO: remove the following hack
. /home/cltbld/release-runner/venv/bin/activate

# Sleep time after a failure, in seconds.
SLEEP_TIME=60
NOTIFY_TO=release@mozilla.com
CONFIG=/home/cltbld/.release-runner.ini
LOGFILE=/var/log/supervisor/release-runner.log

CURR_DIR=$(cd $(dirname $0); pwd)
HOSTNAME=`hostname -s`

cd $CURR_DIR

python release-runner.py -c $CONFIG
RETVAL=$?
# Exit code 5 is a failure during polling. We don't want to send mail about
# this, because it will just try again after sleeping.
if [[ $RETVAL == 5 ]]; then
    sleep $SLEEP_TIME;
# Any other non-zero exit code is some other issue, and we should send mail
# about it.
elif [[ $RETVAL != 0 ]]; then
    (
        echo "Release runner encountered a runtime error: "
        tail -n20 $LOGFILE
        echo
        echo "The full log is available on $HOSTNAME in $LOGFILE"
        echo "I'll sleep for $SLEEP_TIME seconds before retry"
        echo
        echo "- release runner"
    ) | mail -s "[release-runner] failed" $NOTIFY_TO

    sleep $SLEEP_TIME
fi
