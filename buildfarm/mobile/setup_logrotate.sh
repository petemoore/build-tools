#!/bin/bash -eu

# This script is to keep track of changes for watch_devices.sh

echo -n "  * Checking symbolic link /builds/logrotate.config exists and is correct ..."

if [ -L '/builds/logrotate.config' ]
then
    if [ "$(stat -c '%U:%G' /builds/logrotate.config)" != 'cltbld:cltbld' ]
    then
        echo " no"
        echo "ERROR: /builds/logrotate.config symbolic link exists, but belongs to $(stat -c '%U:%G' /builds/logrotate.config) - it should belong to cltbld:cltbld" >&2
        exit 66
    fi
    if [ "$(stat -c '%N' /builds/logrotate.config)" != "\`/builds/logrotate.config' -> \`/builds/tools/buildfarm/mobile/logrotate.config'" ]
    then
        echo " no"
        echo "ERROR: /builds/logrotate.config exists as a symbolic link, but isn't pointing to \`/builds/tools/buildfarm/mobile/logrotate.config'" >&2
        echo "ERROR: Instead it is pointing to $(stat -c '%N' /builds/logrotate.config)" >&2
        exit 65
    fi
    echo " yes"
else
    if [ ! -e '/builds/logrotate.config' ]
    then
        echo " no"
        echo "     -> Creating missing symbolic link /builds/logrotate.config -> /builds/tools/buildfarm/mobile/logrotate.config for cltbld:cltbld ..."
        echo -n '*ROOT* '
        if su -c 'ln -s /builds/tools/buildfarm/mobile/logrotate.config /builds/logrotate.config; chown -h cltbld:cltbld /builds/logrotate.config'
        then
            echo "     -> Successfully created link \`/builds/logrotate.config' -> \`/builds/tools/buildfarm/mobile/logrotate.config' for cltbld:cltbld"
        else
            echo "ERROR: Could not create symbolic link \`/builds/logrotate.config' -> \`/builds/tools/buildfarm/mobile/logrotate.config' for cltbld:cltbld" >&2
            exit 67
        fi
    else
        echo " no"
        echo "ERROR: /builds/logrotate.config exists, but is not a symbolic link. Please delete it, and try again." >&2
        exit 64
    fi
fi

echo -n "  * Checking /builds/watcher_rolled_logs exists ..."
if [ ! -e '/builds/watcher_rolled_logs' ]
then
    echo " no"
    echo "*ROOT* "
    su -c 'mkdir /builds/watcher_rolled_logs; chown cltbld:cltbld /builds/watcher_rolled_logs'
else
    echo " yes"
fi

echo -n "  * Checking /builds/logrotate.log exists ..."
if [ ! -e '/builds/logrotate.log' ]
then
    echo " no"
    echo "*ROOT* "
    su -c 'touch /builds/logrotate.log; chown cltbld:cltbld /builds/logrotate.log'
else
    echo " yes"
fi

echo -n "  * Checking /builds/logrotate.state exists ..."
if [ ! -e '/builds/logrotate.state' ]
then
    echo " no"
    echo "*ROOT* "
    su -c 'touch /builds/logrotate.state; chown cltbld:cltbld /builds/logrotate.state'
else
    echo " yes"
fi

# Temporarily turn off error checking, since crontab -l can give nonzero return code if no crontab installed...
set +e

echo -n "  * Checking if watch_devices.sh is in crontab ..."
WATCH_DEVICES_ALREADY_IN_CRON="$(crontab -l | sed 's/#.*//' | grep "watch_devices\.sh" | wc -l)"
    
if [ "${WATCH_DEVICES_ALREADY_IN_CRON}" -eq 0 ] 
then
    echo " no"
    # simply appending using sed '$a....' does not work if crontab is empty - $a only works if there is at least one character!
    # therefore in this case we will create a temporary file and append the new task to it....
    TEMP_CRONTAB="$(mktemp)"
    CRONTAB_NOHEADER=Y crontab -l > "${TEMP_CRONTAB}"
    {
        echo
        echo '# every 5 mins run watch_devices.sh'
        echo '*/5 *   *   *   * /builds/watch_devices.sh > /dev/null 2>&1'
    } >> "${TEMP_CRONTAB}"
    echo "     -> Updating crontab with watch_devices.sh ..."
    crontab "${TEMP_CRONTAB}"
    rm -f "${TEMP_CRONTAB}"
else
    echo " yes"
fi  

echo -n "  * Checking if logrotate is in crontab ..."
LOG_ROTATE_ALREADY_IN_CRON="$(crontab -l | sed 's/#.*//' | grep "/builds/logrotate\.state" | wc -l)"
    
if [ "${LOG_ROTATE_ALREADY_IN_CRON}" -eq 0 ] 
then
    echo " no"
    # simply appending using sed '$a....' does not work if crontab is empty - $a only works if there is at least one character!
    # therefore in this case we will create a temporary file and append the new task to it....
    TEMP_CRONTAB="$(mktemp)"
    CRONTAB_NOHEADER=Y crontab -l > "${TEMP_CRONTAB}"
    {
        echo
        echo '# rotate watcher logs at 23:59 each evening (local time = PDT) (00:00 would give them the wrong date and run at same time as 00:00 watch_devices.sh execution)'
        echo '59  23  *   *   * /usr/sbin/logrotate -s /builds/logrotate.state -v /builds/logrotate.config >> /builds/logrotate.log 2>&1'
    } >> "${TEMP_CRONTAB}"
    echo "     -> Updating crontab with logrotate ..."
    crontab "${TEMP_CRONTAB}"
    rm -f "${TEMP_CRONTAB}"
else
    echo " yes"
fi  

set -e
