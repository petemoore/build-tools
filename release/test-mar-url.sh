#!/bin/bash
mar_url="${1}"
mar_required_size="${2}"
# failures is an exported env variable

header_file="$(mktemp -t http_header.XXXXXX)"
# strip out dos line returns from header if they occur
curl --retry 5 --retry-max-time 30 -k -s -I -L "${mar_url}" 2>&1 | sed "s/$(printf '\r')//" > "${header_file}"

# check file size matches what was written in update.xml
mar_actual_size="$(cat "${header_file}" | sed -n 's/^Content-Length: //p')"
mar_actual_url="$(cat "${header_file}" | sed -n 's/^Location: //p')"

if [ "${mar_actual_size}" == "${mar_required_size}" ]
then
    echo "$(date):  Mar file ${mar_url} => ${mar_actual_url} available with correct size (${mar_actual_size} bytes)" >&2
elif [ -z "${mar_actual_size}" ]
then
    echo "$(date):  FAILURE: Could not retrieve http header for mar file from ${mar_url}" >&2
    echo "NO_MAR_FILE ${mar_url} ${mar_actual_url}" >> "${failures}"
else
    echo "$(date):  FAILURE: Mar file incorrect size - should be ${mar_required_size} bytes, but is ${mar_actual_size} bytes - ${mar_url} => ${mar_actual_size}" >&2
    echo "MAR_FILE_WRONG_SIZE ${mar_url} ${mar_actual_url} ${mar_required_size} ${mar_actual_size}" >> "${failures}"
fi

rm "${header_file}"
