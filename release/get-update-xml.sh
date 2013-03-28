#!/bin/bash

update_url="${1}"
patch_types="${2//,/ }"
failures="${3}"
update_xml="$(mktemp -t update.xml.XXXXXX)"
curl --retry 5 --retry-max-time 30 -k -s -L "${update_url}" > "${update_xml}" || echo "FAILURE: Could not retrieve http header for update.xml file from ${update_url}" >> "${failures}"
for patch_type in ${patch_types}
do  
    mar_url="$(cat "${update_xml}" | sed -n 's/.*<patch .*type="'"${patch_type}"'".* URL="\([^"]*\)".*/\1/p' | sed 's/\&amp;/\&/g')"
    [ -z "${mar_url}" ] && echo "FAILURE: No patch type '${patch_type}' found in update.xml from ${update_url}" >> "${failures}" || echo "${mar_url}" "${failures}"
done
rm "${update_xml}"
