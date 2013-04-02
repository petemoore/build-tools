#!/bin/bash
mar_url="${1}"
mar_required_size="${2}"
failures="${3}"

header_file="$(mktemp -t http_header.XXXXXX)"
curl --retry 5 --retry-max-time 30 -k -s -I -L "${mar_url}" 2>&1 > "${header_file}"

# check file size matches what was written in update.xml
mar_actual_size="$(cat "${header_file}" | sed -n 's/^Content-Length: \([0-9]*\).*/\1/p')"
mar_actual_url="$(cat "${header_file}" | sed -n 's/Location: //p')"

if [ "${mar_actual_size}" == "${mar_required_size}" ]
then
    echo "${mar_url} succeeded with correct size (${mar_actual_size} bytes)"
    echo "Canonical mar url: ${mar_actual_url}"
elif [ -z "${mar_actual_size}" ]
then
    echo "FAILURE: Could not retrieve http header for mar file from ${mar_url}" | tee -a "${failures}"
else
    echo "FAILURE: Mar file incorrect size - should be ${mar_required_size} bytes, but is ${mar_actual_size} bytes" | tee -a "${failures}"
fi

rm "${header_file}"
