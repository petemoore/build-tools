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

function show_cfg_file_entries {
    local update_xml_url="${1}"
    cat "${update_xml_urls}" | cut -f1 -d' ' | grep -Fn "${update_xml_url}" | sed 's/:.*//' | while read match_line_no
    do
        cfg_file="$(cat "${update_xml_urls}" | sed -n "${match_line_no}p" | cut -f3 -d' ')"
        cfg_line_no="$(cat "${update_xml_urls}" | sed -n "${match_line_no}p" | cut -f4 -d' ')"
        log "        ${cfg_file} line ${cfg_line_no}: $(cat "${cfg_file}" | sed -n "${cfg_line_no}p")"
    done
}

function show_update_xml_entries {
    local mar_url="${1}"
    cat "${update_xml_to_mar}" | cut -f3 -d' ' | grep -Fn "${mar_url}" | sed 's/:.*//' | while read match_line_no
    do
        update_xml_url="$(cat "${update_xml_to_mar}" | sed -n "${match_line_no}p" | cut -f1 -d' ')"
        patch_type="$(cat "${update_xml_to_mar}" | sed -n "${match_line_no}p" | cut -f2 -d' ')"
        mar_size="$(cat "${update_xml_to_mar}" | sed -n "${match_line_no}p" | cut -f4 -d' ')"
        update_xml_actual_url="$(cat "${update_xml_to_mar}" | sed -n "${match_line_no}p" | cut -f5 -d' ')"
        log "        ${update_xml_url}"
        [ -n "${update_xml_actual_url}" ] && log "            which redirected to: ${update_xml_actual_url}"
        log "            This contained an entry for:"
        log "                patch type: ${patch_type}"
        log "                mar size: ${mar_size}"
        log "                mar url: ${mar_url}"
        log "            This update.xml file above was retrieved because of the following cfg file entries:"
        show_cfg_file_entries "${update_xml_url}" | sed 's/        /                /'
    done
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
# each line starts with an error code, and then a white-space separated list of
# entries related to the exception that occured
# e.g.
#
# UPDATE_XML_UNAVAILABLE http://fake.aus.server.org/update/1/Firefox/4.0b9/20110110191600/Linux_x86-gcc3/uk/releasetest/update.xml?force=1
# PATCH_TYPE_MISSING http://revolutioner.org/update/1/Firefox/4.0b15/20101214164501/Linux_x86-gcc3/zh-CN/releasetest/update.xml?force=1 complete 
# PATCH_TYPE_MISSING https://aus2.mozilla.org/update/1/Firefox/4.0b12/20110222205441/Linux_x86-gcc3/dummy-locale/releasetest/update.xml?force=1 complete https://aus3.mozilla.org/update/1/Firefox/4.0b12/20110222205441/Linux_x86-gcc3/dummy-locale/releasetest/update.xml?force=1
# NO_MAR_FILE http://download.mozilla.org/?product=firefox-12.0000-complete&os=linux&lang=zu&force=1
#
# export variable, so it is inherited by subprocesses (get-update-xml.sh and test-mar-url.sh)
export failures="$(mktemp -t failures.XXXXXX)"

# this file will store associations between update xml files and the target mar files
# so that if there is a failure, we can report in the logging which update.xml file caused us
# to look at that mar file
#
# export variable, so it is inherited by subprocesses (get-update-xml.sh and test-mar-url.sh)
export update_xml_to_mar="$(mktemp -t update.xml-to-mar.XXXXXX)"

# this temporary file will list all update urls that need to be checked, in this format:
# <update url> <comma separated list of patch types> <cfg file that requests it> <line number of config file>
# e.g.
# https://aus2.mozilla.org/update/1/Firefox/18.0/20130104154748/Linux_x86_64-gcc3/zh-TW/releasetest/update.xml?force=1 complete moz20-firefox-linux64-major.cfg 3
# https://aus2.mozilla.org/update/1/Firefox/18.0/20130104154748/Linux_x86_64-gcc3/zu/releasetest/update.xml?force=1 complete moz20-firefox-linux64.cfg 7
# https://aus2.mozilla.org/update/1/Firefox/19.0/20130215130331/Linux_x86_64-gcc3/ach/releasetest/update.xml?force=1 complete,partial moz20-firefox-linux64-major.cfg 11
# https://aus2.mozilla.org/update/1/Firefox/19.0/20130215130331/Linux_x86_64-gcc3/af/releasetest/update.xml?force=1 complete,partial moz20-firefox-linux64.cfg 17
update_xml_urls="$(mktemp -t update_xml_urls.XXXXXX)"

# this temporary file will list all the mar download urls to be tested, in this format:
# <mar url>
# e.g.
# http://download.mozilla.org/?product=firefox-20.0-partial-18.0.2&os=linux64&lang=zh-TW&force=1
# http://download.mozilla.org/?product=firefox-20.0-partial-18.0.2&os=linux64&lang=zu&force=1
# http://download.mozilla.org/?product=firefox-20.0-partial-19.0.2&os=linux64&lang=ach&force=1
# http://download.mozilla.org/?product=firefox-20.0-partial-19.0.2&os=linux64&lang=af&force=1
mar_urls="$(mktemp -t mar_urls.XXXXXX)"

# generate full list of update.xml urls, followed by patch types,
# as defined in the specified config files - and write into "${update_xml_urls}" file
aus_server="https://aus2.mozilla.org"
for cfg_file in "${@}"
do
    line_no=0
    cat "${cfg_file}" | sed 's/betatest/releasetest/;s/esrtest/releasetest/' | while read config_line
    do
        let line_no++
        # to avoid contamination between iterations, reset variables
        # each loop in case they are not declared
        # aus_server is not "cleared" each iteration - to be consistent with previous behaviour of old
        # final-verification.sh script - might be worth reviewing if we really want this behaviour
        release="" product="" platform="" build_id="" locales="" channel="" from="" patch_types="complete"
        eval "${config_line}"
        for locale in ${locales}
        do
            echo "${aus_server}/update/1/$product/$release/$build_id/$platform/$locale/$channel/update.xml?force=1" "${patch_types// /,}" "${cfg_file}" "${line_no}"
        done
    done
done > "${update_xml_urls}"

# download update.xml files and grab the mar urls from downloaded file for each patch type required
cat "${update_xml_urls}" | cut -f1-2 -d' ' | sort -u | xargs -n2 "-P${MAX_PROCS}" ../get-update-xml.sh  > "${mar_urls}"

# download http header for each mar url
cat "${mar_urls}" | sort -u | xargs -n2 "-P${MAX_PROCS}" ../test-mar-url.sh

log ''
log 'Stopping stopwatch...'
STOP_TIME="$(date +%s)"

number_of_failures="$(cat "${failures}" | wc -l | sed 's/ //g')"
number_of_update_xml_urls="$(cat "${update_xml_urls}" | wc -l | sed 's/ //g')"
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
    while read failure_code entry1 entry2 entry3 entry4
    do
        case "${failure_code}" in

            UPDATE_XML_UNAVAILABLE) 
                update_xml_url="${entry1}"
                log "FAILURE: Update xml file not available"
                log "    Download url: ${update_xml_url}"
                log "    This url was tested because of the following cfg file entries:"
                show_cfg_file_entries "${update_xml_url}"
                log ""
                ;;

            UPDATE_XML_REDIRECT_FAILED) 
                update_xml_url="${entry1}"
                update_xml_actual_url="${entry2}"
                log "FAILURE: Update xml file not available at *redirected* location"
                log "    Download url: ${update_xml_url}"
                log "    Redirected to: ${update_xml_actual_url}"
                log "    It could not be downloaded from this url."
                log "    This url was tested because of the following cfg file entries:"
                show_cfg_file_entries "${update_xml_url}"
                log ""
                ;;

            PATCH_TYPE_MISSING) 
                update_xml_url="${entry1}"
                patch_type="${entry2}"
                update_xml_actual_url="${entry3}"
                log "FAILURE: Patch type '${patch_type}' not present in the downloaded update.xml file."
                log "    Update xml file downloaded from: ${update_xml_url}"
                [ -n "${update_xml_actual_url}" ] && log "    This redirected to the download url: ${update_xml_actual_url}"
                log "    This url and patch type combination was tested due to the following cfg file entries:"
                show_cfg_file_entries "${update_xml_url}"
                log ""
                ;;

            NO_MAR_FILE)
                mar_url="${entry1}"
                mar_actual_url="${entry2}"
                log "FAILURE: Could not retrieve mar file"
                log "    Mar file url: ${mar_url}"
                [ -n "${mar_actual_url}" ] && log "    This redirected to: ${mar_actual_url}"
                log "    The mar file could not be downloaded from this location."
                log "    The mar download was tested because it was referenced in the following update xml file(s):"
                show_update_xml_entries "${mar_url}"
                log ""
                ;;

            MAR_FILE_WRONG_SIZE) 
                mar_url="${entry1}"
                mar_actual_url="${entry2}"
                mar_required_size="${entry3}"
                mar_actual_size="${entry4}"
                log "FAILURE: Mar file is wrong size"
                log "    Mar file url: ${mar_url}"
                [ -n "${mar_actual_url}" ] && log "    This redirected to: ${mar_actual_url}"
                log "    The http header of the mar file url says that the mar file is ${mar_actual_size} bytes."
                log "    One or more of the following update.xml file(s) says that the file should be ${mar_required_size} bytes."
                log "    These are the update xml file(s) that referenced this mar:"
                show_update_xml_entries "${mar_url}"
                log ""
                ;;

            *)
                log "ERROR: Unknown failure code - '${failure_code}'"
                log "ERROR: This is a serious bug in this script."
                log "ERROR: Only known failure codes are: UPDATE_XML_UNAVAILABLE, UPDATE_XML_REDIRECT_FAILED, PATCH_TYPE_MISSING, NO_MAR_FILE, MAR_FILE_WRONG_SIZE"
                log "ERROR: Data from failure is: ${entry1} ${entry2} ${entry3} ${entry4}"
                log ''
                ;;

        esac
    done < "${failures}"
    exit_code=1
fi


log ''
log '===================================='
log 'KEY STATS'
log '===================================='
log ''
log "Config files scanned:                       ${#@}"
log "Update xml files downloaded and parsed:     ${number_of_update_xml_urls}"
log "Mar files found:                            ${number_of_mar_urls}"
log "Failures:                                   ${number_of_failures}"
log "Parallel processes used (maximum limit):    ${MAX_PROCS}"
log "Execution time:                             $((STOP_TIME-START_TIME)) seconds"
log ''

rm "${failures}"
rm "${update_xml_urls}"
rm "${mar_urls}"

exit ${exit_code}
