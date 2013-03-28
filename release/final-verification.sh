#!/bin/bash

# In the updates subdirectory of the directory this script is in,
# there are a bunch of config files. You should call this script,
# passing the names of one or more of those files as parameters
# to this script.

function log {
    echo "$(date):  ${1}"
}

function usage {
    log "Usage:"
    log "    $(basename "${0}") [-p MAX_PROCS] config1 [config2 config3 config4 ...]"
    log "    $(basename "${0}") -h"
}

echo -n "$(date):  Command called:"
for ((INDEX=0; INDEX<=$#; INDEX+=1))
do
    echo -n " '${!INDEX}'"
done
echo ''
log "From directory: '$(pwd)'"
log ''
log "Parsing arguments..."

# default is 128 parallel processes
MAX_PROCS=128
BAD_ARG=0
BAD_FILE=0
while getopts p:h OPT
do
    case "${OPT}" in
        p) MAX_PROCS="${OPTARG}";;
        h) usage
           exit;;
        *) BAD_ARG=1;;
    esac
done
shift "$((OPTIND - 1))"

# invalid option specified
[ "${BAD_ARG}" == 1 ] && exit 66

log "Checking one or more config files have been specified..."
if [ $# -lt 1 ]
then
    usage
    log "ERROR: You must specify one or more config files"
    exit 64
fi

log "Checking whether MAX_PROCS is a number..."
if ! let x=MAX_PROCS 2>/dev/null
then
    usage
    log "ERROR: MAX_PROCS must be a number (-p option); you specified '${MAX_PROCS}' - this is not a number."
    exit 65
fi

# config files are in updates subdirectory below this script
cd "$(dirname "${0}")/updates"

log "Checking specified config files all exist relative to directory '$(pwd)':"
log ''
for file in "${@}"
do
    if [ -f "${file}" ]
    then
        log "  * '${file}' ok"
    else
        log "  * '${file}' missing"
        BAD_FILE=1
    fi
done
log ''

# invalid config specified
if [ "${BAD_FILE}" == 1 ]
then
    log "ERROR: Specified config file(s) missing relative to '$(pwd)' directory - see above."
    exit 67
fi

log "All checks completed successfully."
log ''
log "Starting stopwatch..."
log ''

START_TIME="$(date +%s)"

# create temporary log file of failures, to output at end of processing
failures="$(mktemp -t failures.XXXXXX)"

# this temporary file will list all update urls that need to be checked, in this format:
# <update url> <comma separated list of patch types> <temp file to store failure messages>
# e.g.
# https://aus2.mozilla.org/update/1/Firefox/18.0/20130104154748/Linux_x86_64-gcc3/zh-TW/releasetest/update.xml?force=1 complete /tmp/failures.S16157
# https://aus2.mozilla.org/update/1/Firefox/18.0/20130104154748/Linux_x86_64-gcc3/zu/releasetest/update.xml?force=1 complete /tmp/failures.S16157
# https://aus2.mozilla.org/update/1/Firefox/19.0/20130215130331/Linux_x86_64-gcc3/ach/releasetest/update.xml?force=1 complete,partial /tmp/failures.S16157
# https://aus2.mozilla.org/update/1/Firefox/19.0/20130215130331/Linux_x86_64-gcc3/af/releasetest/update.xml?force=1 complete,partial /tmp/failures.S16157
update_urls="$(mktemp -t update_urls.XXXXXX)"

# this temporary file will list all the mar download urls to be tested, in this format:
# <mar url> <temp file to store failure messages>
# e.g.
# http://download.mozilla.org/?product=firefox-20.0-partial-18.0.2&os=linux64&lang=zh-TW&force=1 /tmp/failures.S16157
# http://download.mozilla.org/?product=firefox-20.0-partial-18.0.2&os=linux64&lang=zu&force=1 /tmp/failures.S16157
# http://download.mozilla.org/?product=firefox-20.0-partial-19.0.2&os=linux64&lang=ach&force=1 /tmp/failures.S16157
# http://download.mozilla.org/?product=firefox-20.0-partial-19.0.2&os=linux64&lang=af&force=1 /tmp/failures.S16157
mar_urls="$(mktemp -t mar_urls.XXXXXX)"

# generate full list of update.xml urls, followed by patch types,
# as defined in the specified config files - and write into "${update_urls}" file
cat "${@}" | sed 's/betatest/releasetest/;s/esrtest/releasetest/' | sort -u | while read config_line
do
    # to avoid contamination between iterations, reset variables
    # each loop in case they are not declared
    release="" product="" platform="" build_id="" locales="" channel="" from="" patch_types="complete" aus_server="https://aus2.mozilla.org"
    eval "${config_line}"
    for locale in ${locales}
    do
        echo "${aus_server}/update/1/$product/$release/$build_id/$platform/$locale/$channel/update.xml?force=1" "${patch_types// /,}" "${failures}"
    done
done | sort -u > "${update_urls}"

# log which urls we are checking, so that user knows which urls will be tested
cat "${update_urls}" | sed -n "s/^\\([^ ]*\\) \\([^ ]*\\).*/$(date):  Downloading update.xml from \\1 for patch type(s): \\2/p"
log ''

# download update.xml files and grab the mar urls from downloaded file for each patch type required
cat "${update_urls}" | xargs -n3 "-P${MAX_PROCS}" ../get-update-xml.sh | sort -u > "${mar_urls}"

# download http header for each mar url
cat "${mar_urls}" | xargs -n2 "-P${MAX_PROCS}" ../test-mar-url.sh | sort -u | sed "s/^/$(date):  /"

log ''
log 'Stopping stopwatch...'
STOP_TIME="$(date +%s)"

number_of_failures="$(cat "${failures}" | wc -l | sed 's/ //g')"
number_of_update_urls="$(cat "${update_urls}" | wc -l | sed 's/ //g')"
number_of_mar_urls="$(cat "${mar_urls}" | wc -l | sed 's/ //g')"

if [ "${number_of_failures}" -eq 0 ]
then
    log
    log "All tests passed successfully."
    log
    exit_code=0
else
    log ''
    log '===================================='
    [ "${number_of_failures}" -gt 1 ] && log "${number_of_failures} FAILURES" || log '1 FAILURE'
    log '===================================='
    log ''
    cat "${failures}" | sort | sed "s/^/$(date):  /"
    exit_code=1
fi


log ''
log '===================================='
log 'KEY STATS'
log '===================================='
log ''
log "Config files scanned:                       ${#@}"
log "Update xml files downloaded and parsed:     ${number_of_update_urls}"
log "Mar files found:                            ${number_of_mar_urls}"
log "Failures:                                   ${number_of_failures}"
log "Parallel processes used (maximum limit):    ${MAX_PROCS}"
log "Execution time:                             $((STOP_TIME-START_TIME)) seconds"
log ''

rm "${failures}"
rm "${update_urls}"
rm "${mar_urls}"

exit ${exit_code}
