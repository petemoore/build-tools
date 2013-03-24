#!/bin/bash

# In the updates subdirectory of the directory this script is in,
# there are a bunch of config files. You should call this script,
# passing the names of one or more of those files as parameters
# to this script.

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "${0}") [list of update verify configs]" >&2
    exit 127
fi

# config files are in updates subdirectory below this script
cd "$(dirname "${0}")/updates"

# create temporary location to download update.xml files
update_xml="$(mktemp -t update.xml.XXXXXX)"
failures="$(mktemp -t failures.XXXXXX)"

# generate full list of update.xml urls, followed by patch types,
# as defined in the specified config files
cat "${@}" | sed 's/betatest/releasetest/;s/esrtest/releasetest/' | sort -u | while read config_line
do
    # to avoid contamination between iterations, reset variables
    # each loop in case they are not declared
    release="" product="" platform="" build_id="" locales="" channel="" from="" patch_types="complete" aus_server="https://aus2.mozilla.org"
    eval "${config_line}"
    for locale in ${locales}
    do
        echo "${aus_server}/update/1/$product/$release/$build_id/$platform/$locale/$channel/update.xml?force=1" "${patch_types}"
    done
done | sort -u | while read update_url patch_types
# Now download update.xml files and grab the mar urls for each
# patch type required
do
    curl --retry 5 --retry-max-time 30 -k -s -L "${update_url}" > "${update_xml}" || echo "ERROR: Could not retrieve http header for update.xml file from ${update_url}" | tee -a "${failures}"
    for patch_type in ${patch_types}
    do
        mar_url="$(cat "${update_xml}" | sed -n 's/.*<patch .*type="'"${patch_type}"'".* URL="\([^"]*\)".*/\1/p')"
        [ -z "${mar_url}" ] && echo "ERROR: No patch type '${patch_type}' mar url found in update.xml from ${update_url}" | tee -a "${failures}" || echo "${mar_url}"
    done
done | sort -u | while read mar_url
do
    # now check availability of mar by downloading its http header (quicker than full download)
    curl --retry 5 --retry-max-time 30 -k -s -I -L "${mar_url}" >/dev/null 2>&1 && echo "${mar_url} succeeded" || echo "ERROR: Could not retrieve http header for mar file from ${mar_url}" | tee -a "${failures}"
done

rm "${update_xml}"

# Now print a summary report - either declare complete success, or list failures
number_of_failures="$(cat "${failures}" | wc -l)"
if [ "${number_of_failures}" -eq 0 ]
then
    echo
    echo "All tests passed successfully"
    echo
    exit_code=0
else
    echo ""
    echo "===================================="
    [ "${number_of_failures}" -gt 1 ] && echo "${number_of_failures} FAILURES" || echo "1 FAILURE"
    echo "===================================="
    echo ""
    cat "${failures}"
    exit_code=1
fi

rm "${failures}"
exit ${exit_code}
