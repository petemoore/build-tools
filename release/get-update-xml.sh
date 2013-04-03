#!/bin/bash

update_xml_url="${1}"
patch_types="${2//,/ }"
# failures is an exported env variable
# update_xml_to_mar is an exported env variable
update_xml="$(mktemp -t update.xml.XXXXXX)"
update_xml_headers="$(mktemp -t update.xml.headers.XXXXXX)"
if curl --retry 5 --retry-max-time 30 -k -s -D "${update_xml_headers}" -L "${update_xml_url}" > "${update_xml}"
then
    update_xml_actual_url="$(cat "${update_xml_headers}" | sed "s/$(printf '\r')//" | sed -n 's/^Location: //p')"
    for patch_type in ${patch_types}
    do  
        mar_url_and_size="$(cat "${update_xml}" | sed -n 's/.*<patch .*type="'"${patch_type}"'".* URL="\([^"]*\)".*size="\([^"]*\)".*/\1 \2/p' | sed 's/\&amp;/\&/g')"
        if [ -z "${mar_url_and_size}" ]
        then
            echo "$(date):  FAILURE: No patch type '${patch_type}' found in update.xml from ${update_xml_url} => ${update_xml_actual_url}" >&2
            echo "PATCH_TYPE_MISSING ${update_xml_url} ${patch_type} ${update_xml_actual_url}" >> "${failures}"
        else
            echo "${mar_url_and_size}"
            echo "$(date):  Retrieved mar url and file size from update.xml file downloaded from ${update_xml_url} => ${update_xml_actual_url}" >&2
            # now log that this update xml and patch combination brought us to this mar url and mar file size
            echo "${update_xml_url} ${patch_type} ${mar_url_and_size} ${update_xml_actual_url}" >> "${update_xml_to_mar}"
        fi
    done
else
    if [ -z "${update_xml_actual_url}" ]
    then
        echo "$(date):  FAILURE: Could not retrieve update.xml from ${update_xml_url}" >&2
        echo "UPDATE_XML_UNAVAILABLE ${update_xml_url}" >> "${failures}"
    else
        echo "$(date):  FAILURE: update.xml from ${update_xml_url} redirected to ${update_xml_actual_url} but could not retrieve update.xml from here" >&2
        echo "UPDATE_XML_REDIRECT_FAILED ${update_xml_url} ${update_xml_actual_url}" >> "${failures}"
    fi
fi
rm "${update_xml}"
rm "${update_xml_headers}"
