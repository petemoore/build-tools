#!/bin/bash -eu

# MAGIC NUMBERS (global)
# used to determine how long we sleep when...
SUCCESS_WAIT=200 # ... seconds after we startup buildbot
FAIL_WAIT=500 # ... seconds after we stop buildbot due to error.flg

log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ${1}" >&2
}
death() {
  log "*** ERROR *** ${1}"
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
  log "buildbot pid is $expected_pid"
  kill -0 $expected_pid >/dev/null 2>&1
  return $?
}

function device_check_exit() {
  rm -rf "/builds/${device}/watcher.lockdir"
  log "Cycle for our device (${device}) complete" >>"/builds/${device}/watcher.log" 2>&1
}

function device_check() {
  local device=$1
  export PYTHONPATH=/builds/sut_tools
  deviceIP=`python -c "import sut_lib;print sut_lib.getIPAddress('$device')" 2> /dev/null`
  log ""
  log ""
  log "Starting cycle for our device ($device = $deviceIP) now"
  if ! check_buildbot_running "${device}"; then
    log "Buildbot is not running"
    if [ -f /builds/$device/disabled.flg ]; then
       death "Not Starting due to disabled.flg" 64
    fi
    if [ -f /builds/$device/error.flg ]; then
      log "error.flg file detected"
      # Clear flag if older than an hour
      if [ `find /builds/$device/error.flg -mmin +60` ]; then
        log "removing $device error.flg (older than an hour) and trying again"
        rm -f /builds/$device/error.flg
      else
        death "Error flag less than an hour old, so exiting" 65
      fi
    fi
    export SUT_NAME=$device
    export SUT_IP=$deviceIP
    if ! python /builds/sut_tools/verify.py $device; then
       log "Verify procedure failed"
       if [ ! -f /builds/$device/error.flg ]; then
           log "error.flg file does not exist, so creating it..."
           echo "Unknown verify failure" | tee "/builds/$device/error.flg"
       else
           log "Verify problem discovered:"
           while read LINE; do
               log "${LINE}"
           done < "/builds/${device}/error.flg"
       fi
       death "Exiting due to verify failure" 66
    fi
    log "starting buildbot slave for device $device (IP=$deviceIP)"
    /builds/tools/buildfarm/mobile/manage_buildslave.sh start $device
    log "Sleeping for ${SUCCESS_WAIT} sec after startup, to prevent premature flag killing"
    sleep ${SUCCESS_WAIT} # wait a bit before checking for an error flag or otherwise
  else # buildbot running
    log "(heartbeat) buildbot is running"
    if [ -f /builds/$device/error.flg -o -f /builds/$device/disabled.flg ]; then
        log "Something wants us to kill buildbot (either error.flg or disabled.flg exists)..."
        set +e # These steps are ok to fail, not a great thing but not critical
        cp /builds/$device/error.flg /builds/$device/error.flg.bak # stop.py will remove error flag o_O
        log "Stopping device $device..."
        python /builds/sut_tools/stop.py --device $device
        # Stop.py should really do foopy cleanups and not touch device
        log "Cleaning up device $device..."
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
    "${0}" "${device}" & 8</dev/null
  done
  log "Watcher completed."
}

# SCRIPT ENTRY POINT HERE...

if [ "$#" -eq 0 ]; then
  watch_launcher 2>&1 | tee -a "/builds/watcher.log"
else
  device="${1}"
  # mkdir is an atomic operation that checks if a directory exists, and creates it if it doesn't
  # atomic operation required so that it operates safely with multiple processes running
  if ! mkdir "/builds/${device}/watcher.lockdir" >/dev/null 2>&1; then
      # should not be possible for a lockdir to be left over, but just in case...
      # if older than an hour, we assume the process has crashed without cleanup
      if find "/builds/${device}/watcher.lockdir" -mmin +60 | grep '' >/dev/null; then
          log "WARN: Removing lock for ${device} which is older than an hour"
          rm -rf "/builds/${device}/watcher.lockdir"
          if ! mkdir "/builds/${device}/watcher.lockdir" >/dev/null 2>&1; then
              death "For an unknown reason, cannot create directory '/builds/${device}/watcher.lockdir'" 69
          fi
      else
          death "device ${device} already being checked by another process" 68
      fi
  fi
  # we've definitely acquired the lock at this point, so create the trap as soon as possible...
  trap "device_check_exit ${device}" EXIT
  device_check "${device}" >>"/builds/${device}/watcher.log" 2>&1
fi
