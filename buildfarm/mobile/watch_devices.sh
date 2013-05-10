#!/bin/bash -eu

# MAGIC NUMBERS (global)
# used to determine how long we sleep when...
CYCLE_WAIT=300 # 5 minutes between cycling of watches for our devices
SUCCESS_WAIT=200 # ... seconds after we startup buildbot
FAIL_WAIT=500 # ... seconds after we stop buildbot due to error.flg

log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ${1}" >&2
}
death() {
  log "${1}"
  exit "${2}"
}

function check_buildbot_running() {
  # returns success if running
  #         !0 if not running
  local device=$1
  if [ ! -f /builds/$device/twistd.pid ]; then
     return 1
  fi
  local expected_pid=`cat /builds/$device/twistd.pid`
  debug "buildbot pid is $expected_pid"
  kill -0 $expected_pid 2>&1 >/dev/null
  return $?
}

function device_check() {
  local device=$1
  export PYTHONPATH=/builds/sut_tools
  deviceIP=`python -c "import sut_lib;print sut_lib.getIPAddress('$device')" 2> /dev/null`
  log "Starting cycle for our device ($device) now"
  if check_buildbot_running; then
    if [ -f /builds/$device/disabled.flg ]; then
       death "Not Starting due to disabled.flg" 64
    fi
    if [ -f /builds/$device/error.flg ]; then
      # Clear flag if older than an hour
      if [ `find /builds/$device/error.flg -mmin +60` ]; then
        log "removing $device error.flg and trying again"
        rm -f /builds/$device/error.flg
      else
        death "Error Flag told us not to start" 65
      fi
    fi
    export SUT_NAME=$device
    export SUT_IP=$deviceIP
    retcode=0
    python /builds/sut_tools/verify.py $device || retcode=$?
    if [ $retcode -ne 0 ]; then
       if [ ! -f /builds/$device/error.flg ]; then
           echo "Unknown verify failure" | tee "/builds/$device/error.flg"
       fi
       death "Verify failed" 66
    fi
    /builds/tools/buildfarm/mobile/manage_buildslave.sh start $device
    log "Sleeping for ${SUCCESS_WAIT} sec after startup, to prevent premature flag killing"
    sleep ${SUCCESS_WAIT} # wait a bit before checking for an error flag or otherwise
  else # buildbot running
    log "(heartbeat) buildbot is running"
    if [ -f /builds/$device/error.flg -o -f /builds/$device/disabled.flg ]; then
        log "Something wants us to kill buildbot..."
        set +e # These steps are ok to fail, not a great thing but not critical
        cp /builds/$device/error.flg /builds/$device/error.flg.bak # stop.py will remove error flag o_O
        python /builds/sut_tools/stop.py --device $device
        # Stop.py should really do foopy cleanups and not touch device
        SUT_NAME=$device python /builds/sut_tools/cleanup.py $device
        mv /builds/$device/error.flg.bak /builds/$device/error.flg # Restore it
        set -e
        log "sleeping for ${FAIL_WAIT} seconds after killing, to prevent startup before master notices"
        sleep ${FAIL_WAIT} # Wait a while before allowing us to turn buildbot back on
    fi
  fi
  log "Cycle for our device ($device) complete"
}


function watch_launcher(){
  log "STARTING Watcher"
  ls -d /builds/{tegra-*[0-9],panda-*[0-9]} 2>/dev/null | sed 's:.*/::' | while read device; do
    log "..checking $device"
    "${0}" "${device}" &
  done
  log "Watcher completed."
}

if [ "$#" -eq 0 ]; then
  watch_launcher 2>&1 | tee -a "/builds/watcher.log"
else
  (
    flock -n 9 || death "lockfile for device ${1} locked by another process" 67
    device_check "${1}"
  ) 9>"/builds/${1}/watcher.lock" >"/builds/${1}/watcher.log" 2>&1
fi
