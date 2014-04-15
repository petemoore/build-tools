#!/bin/bash -e

# Explicitly unset any pre-existing environment variables to avoid variable collision
unset DRY_RUN
WIKI_TEXT_ADDITIONS_FILE=""

usage() {
    echo "Usage: $0 -h"
    echo "Usage: $0 -d"
    echo "Usage: $0 [-d] -w WIKI_TEXT_ADDITIONS_FILE"
    echo
    echo "    -d:                           Dry run; will not make changes, only validates login."
    echo "    -h:                           Display help."
    echo "    -w WIKI_TEXT_ADDITIONS_FILE:  File containing wiki markdown to insert into wiki page."
}

echo "  * Parsing parameters..."
# Parse parameters passed to this script
while getopts ":dhw:" opt; do
    case "${opt}" in
        d)  DRY_RUN=1
            ;;
        h)  usage()
            exit 0
            ;;
        w)  WIKI_TEXT_ADDITIONS_FILE="${opt}"
            ;;
        ?)  usage >&2
            exit 1
            ;;
    esac
done

DRY_RUN="${DRY_RUN:-0}"

if [ -z "${WIKI_TEXT_ADDITIONS_FILE}" ]; then
    echo "Must provide a file containing additional wiki text to embed, e.g. '${0}' -w 'reconfig-bugs.wikitext'" >&2
    echo "Exiting..." >&2
    exit 64
fi

if [ ! -f "${WIKI_TEXT_ADDITIONS_FILE}" ]; then
    echo "File '${WIKI_TEXT_ADDITIONS_FILE}' not found. Working directory is '$(pwd)'." >&2
    echo "This file should contain additional wiki content to be inserted in https://wiki.mozilla.org/ReleaseEngineering/Maintenance." >&2
    echo "Exiting..." >&2
    exit 65
fi

if [ -z "${WIKI_USERNAME}" ]; then
    echo "Environment variable WIKI_USERNAME must be set for publishing wiki page to https://wiki.mozilla.org/ReleaseEngineering/Maintenance" >&2
    echo "Exiting..." >&2
    exit 66
else
    echo "  * Environment variable WIKI_USERNAME defined"
fi

if [ -z "${WIKI_PASSWORD}" ]; then
    echo "Environment variable WIKI_PASSWORD must be set for publishing wiki page to https://wiki.mozilla.org/ReleaseEngineering/Maintenance" >&2
    echo "Exiting..." >&2
    exit 67
else
    echo "  * Environment variable WIKI_PASSWORD defined"
fi

# create some temporary files
current_content="$(mktemp -t current-content.XXXXXXXXXX)"
new_content="$(mktemp -t new-content.XXXXXXXXXX)"
cookie_jar="$(mktemp -t cookie-jar.XXXXXXXXXX)"

echo "  * Retrieving current wiki text of https://wiki.mozilla.org/ReleaseEngineering/Maintenance..."
curl -s 'https://wiki.mozilla.org/ReleaseEngineering/Maintenance&action=raw' >> "${current_content}"

# find first "| in production" line in the current content, and grab line number
old_line="$(sed -n '/^| in production$/=' "${current_content}" | head -1)"

echo "  * Preparing wiki page to include new content..."
# create new version of whole page, and put in "${new_content}" file...
{
    # old content, up to 2 lines before the first "| in production" line
    sed -n 1,$((old_line-2))p "${current_content}"
    # the new content to add
    cat "${WIKI_TEXT_ADDITIONS_FILE}"
    # the rest of the page (starting from line before "| in production"
    sed -n $((old_line-1)),\$p "${current_content}"
} > "${new_content}"

# login, store cookies in "${cookie_jar}" temporary file, and get login token...
echo "  * Logging in to wiki and getting login token and session cookie..."
json="$(curl -s -c "${cookie_jar}" -d action=login -d lgname="${WIKI_USERNAME}" -d lgpassword="${WIKI_PASSWORD}" -d format=json 'https://wiki.mozilla.org/api.php')"
login_token="$(echo "${json}" | sed -e 's/.*"token":"//' -e 's/".*//')"
# login again, using login token received (see https://www.mediawiki.org/wiki/API:Login)
echo "  * Logging in again, and passing login token just received..."
curl -s -b "${cookie_jar}" -d action=login -d lgname="${WIKI_USERNAME}" -d lgpassword="${WIKI_PASSWORD}" -d lgtoken="${login_token}" 'https://wiki.mozilla.org/api.php' 2>&1 > login.output
# get an edit token, remembering to pass previous cookies (see https://www.mediawiki.org/wiki/API:Edit)
echo "  * Retrieving an edit token for making wiki changes..."
edit_token="$(curl -b "${cookie_jar}" -s -d action=query -d prop=info -d intoken=edit -d titles=ReleaseEngineering/Maintenance 'https://wiki.mozilla.org/api.php' | sed -n 's/.*edittoken=&quot;//p' | sed -n 's/&quot;.*//p')"
# now post new content...
EXIT_CODE=0
if [ "${DRY_RUN}" == 0 ]; then
    publish_log="$(mktemp -t publish-log.XXXXXXXXXX)"
    echo "  * Publishing updated maintenance page to https://wiki.mozilla.org/ReleaseEngineering/Maintenance..."
    curl -s -b "${cookie_jar}" -H 'Content-Type:application/x-www-form-urlencoded' -d action=edit -d title='ReleaseEngineering/Maintenance' -d 'summary=reconfig' -d "text=$(cat "${new_content}")" --data-urlencode token="${edit_token}" 'https://wiki.mozilla.org/api.php' 2>&1 > update.output
    echo "  * Checking whether publish was successful..."
    if grep -q Success "${publish_log}"; then
        echo "  * Maintenance wiki updated successfully."
    else
        echo "  * Failed to update wiki page https://wiki.mozilla.org/ReleaseEngineering/Maintenance."
        EXIT_CODE=68
    fi
    rm "${publish_log}"
else
    echo "  * Not publishing changes to https://wiki.mozilla.org/ReleaseEngineering/Maintenance since this is a dry run..."
fi
# Be kind and logout.
echo "  * Logging out of wiki"
curl -s -b "${cookie_jar}" -d action=logout 'https://wiki.mozilla.org/api.php'

# remove temporary files
rm "${cookie_jar}"
rm "${new_content}"
rm "${current_content}"

exit "${EXIT_CODE}"