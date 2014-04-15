#!/bin/bash -e

# Explicitly unset any pre-existing environment variables to avoid variable collision
unset DRY_RUN FORCE_RECONFIG MERGE_TO_PRODUCTION UPDATE_WIKI RECONFIG_DIR USE_TMUX WIKI_CREDENTIALS_FILE WIKI_USERNAME WIKI_PASSWORD

usage() {
    echo "This script can be used to reconfig interactively, or non-interactively. It will merge"
    echo "buildbotcustom, buildbot-configs, mozharness from default to production(-0.8)."
    echo "It will then reconfig, and afterwards if all was successful, it will also update the"
    echo "wiki page https://wiki.mozilla.org/ReleaseEngineering/Maintenance."
    echo
    echo "Usage: $0 -h"
    echo "Usage: $0 [-d] [-f] [-m] [-n] [-r RECONFIG_DIR] [-t] [-w WIKI_CREDENTIALS_FILE]"
    echo
    echo "    -d:                        Dry run; will not make changes."
    echo "    -f:                        Force reconfig, even if no changes merged."
    echo "    -h:                        Display help."
    echo "    -m:                        No merging of default -> production(-0.8) of hg branches."
    echo "    -n:                        No wiki update."
    echo "    -r RECONFIG_DIR:           Use directory RECONFIG_DIR for storing temporary files"
    echo "                               (default is /tmp/reconfig). This directory, and any"
    echo "                               necessary parent directories will be created if required."
    echo "    -t:                        Use TMUX for reconfig (default is *not* to use TMUX)."
    echo "    -w WIKI_CREDENTIALS_FILE:  Source WIKI_USERNAME and WIKI_PASSWORD env vars from file"
    echo "                               WIKI_CREDENTIALS_FILE (default is ~/.wikiwriter/config)."
}

echo "  * Parsing parameters..."
# Parse parameters passed to this script
while getopts ":dfhnr:tw:" opt; do
    case "${opt}" in
        d)  DRY_RUN=1
            ;;
        f)  FORCE_RECONFIG=1
            ;;
        h)  usage()
            exit 0
            ;;
        m)  MERGE_TO_PRODUCTION=0
            ;;
        n)  UPDATE_WIKI=0
            ;;
        r)  RECONFIG_DIR="${opt}"
            ;;
        t)  USE_TMUX=1
            ;;
        w)  WIKI_CREDENTIALS_FILE="${opt}"
            ;;
        ?)  usage >&2
            exit 1
            ;;
    esac
done

DRY_RUN="${DRY_RUN:-0}"
FORCE_RECONFIG="${FORCE_RECONFIG:-0}"
MERGE_TO_PRODUCTION="${MERGE_TO_PRODUCTION:-1}"
UPDATE_WIKI="${UPDATE_WIKI:-1}"
RECONFIG_DIR="${RECONFIG_DIR:-/tmp/reconfig}"
USE_TMUX="${USE_TMUX:-0}"
WIKI_CREDENTIALS_FILE="${WIKI_CREDENTIALS_FILE:-${HOME}/.wikiwriter/config}"

# Simple function to output the name of this script and the options that were passed to it
function command_called {
    echo -n "Command called:"
    for ((INDEX=0; INDEX<=$#; INDEX+=1))
    do
        echo -n " '${!INDEX}'"
    done
    echo ''
    echo "From directory: '$(pwd)'"
}

##### Now check parsed parameters are valid...

echo "  * Validating parameters..."
command_called "${@}" | sed 's/^/  * /'

if [ "${DRY_RUN}" == 0 ]; then
    echo "  * Not a dry run; will enact changes."
else
    echo "  * Dry run specified; no changes will be made."
fi

if [ ! -d "${RECONFIG_DIR}" ]; then
    echo "  * Creating directory '${RECONFIG_DIR}'..."
    if ! mkdir -p "${RECONFIG_DIR}"; then
        command_called "${@}" >&2
        echo "Directory '${RECONFIG_DIR}' could not be created from directory '$(pwd)'." >&2
        exit 64
    fi
else
    echo "  * Reconfig directory '${RECONFIG_DIR}' exists - OK"
fi

# Convert ${RECONFIG_DIR} to an absolute directory, in case it is relative, by stepping into it...
pushd "${RECONFIG_DIR}"
if [ "${RECONFIG_DIR}" != "$(pwd)" ]; then
    echo "  * Reconfig directory absolute path: '$(pwd)'"
fi
RECONFIG_DIR="$(pwd)"
popd

# Check if a previous reconfig did not complete
if [ -f "${RECONFIG_DIR}/merged_flag" ]; then
    echo "  * It looks like a previous reconfig did not complete"
    echo "  * Checking if shell is interactive..."
    case $- in
        *i*)  # interactive shell
              echo "  * Please select one of the following options:"
              echo "        1) Continue with existing reconfig (e.g. if you have resolved a merge conflict)"
              echo "        2) Delete saved state for existing reconfig, and start from fresh"
              echo "        3) Abort and exit reconfig process"
              choice=''
              while [ "${choice}" != 1 ] && [ "${choice}" != 2 ] && [ "${choice}" != 3 ]; do
                  echo -n "    Your choice: "
                  read choice
              done
              case "${choice}" in
                  1) echo "  * Continuing with stalled reconfig..."
                     ;;
                  2) echo "  * Recreating directory '${RECONFIG_DIR}'..."
                     rm -rf "${RECONFIG_DIR}"
                     mkdir "${RECONFIG_DIR}"
                     ;;
                  3) echo "  * Aborting reconfig..."
                     exit 68
                     ;;
              esac
              ;;
        *)    # non-interactive shell
              echo "  * Non-interactive shell detected, cannot ask whether to continue or not, therefore aborting..."
              exit 67
              ;;
    esac
fi

# Only validate wiki credentials if we are updating wiki...
if [ "${UPDATE_WIKI}" == '1' ]; then
    echo "  * Wiki update enabled."
    # To avoid user getting confused about parent directory, tell user the
    # absolute path of the credentials file...
    PARENT_DIR="$(dirname "${WIKI_CREDENTIALS_FILE}")"
    pushd "${PARENT_DIR}"
    ABS_WIKI_CREDENTIALS_FILE="$(pwd)/$(basename "${WIKI_CREDENTIALS_FILE}")"
    popd
    if [ "${WIKI_CREDENTIALS_FILE}" == "${ABS_WIKI_CREDENTIALS_FILE}" ]; then
        echo "  * Wiki credentials file '${WIKI_CREDENTIALS_FILE}'"
    else
        echo "  * Wiki credentials file '${WIKI_CREDENTIALS_FILE}' has absolute path '${ABS_WIKI_CREDENTIALS_FILE}'"
    fi
    if [ ! -e "${ABS_WIKI_CREDENTIALS_FILE}" ]; then
        if [ "${DRY_RUN}" == 0 ]; then
            echo "  * Wiki credentials file '${ABS_WIKI_CREDENTIALS_FILE}' not found; creating..." >&2
            {
                echo 'export WIKI_USERNAME="naughtymonkey"'
                echo 'export WIKI_PASSWORD="nobananas"'
            } > "${WIKI_CREDENTIALS_FILE}"
            echo "  * Created credentials file '${PARENT_DIR}/${FILENAME}'. Please edit this file, setting appropriate values, then rerun." >&2
            command_called "${@}" >&2
        else
            echo "  * Wiki credentials file '${ABS_WIKI_CREDENTIALS_FILE}' not found; but dry run - so not creating."
        fi
        exit 65
    else
        source "${WIKI_CREDENTIALS_FILE}"
    fi
else
    echo "  * Not updating wiki."
fi

# Now step into directory this script is in...
cd "$(dirname "${0}")"

if [ "${UPDATE_WIKI}" == '1' ]; then
    # Now validate wiki credentials by performing a dry run...
    echo "  * Testing login credentials for wiki..."
    ./update_maintenance_wiki.sh -d
fi

# Test python version, and availability of fabric...
echo "  * Checking python version is 2.7..."
if ! python --version 2>&1 | grep -q '^Python 2\.7'; then
    echo "  * Python version 2.7 not found - please make sure python 2.7 is in your PATH." >&2
    exit 66
fi

echo "  * Checking fabric module is available in python environment..."
if ! python -c 'import fabric' >/dev/null 2>&1; then
    echo "  * Fabric module not found"
    if [ ! -e "${RECONFIG_DIR}/fabric-virtual-env" ]; then
        echo "  * Creating virtualenv directory '${RECONFIG_DIR}/fabric-virtual-env' for fabric instalation..."
        virtualenv "${RECONFIG_DIR}/fabric-virtual-env"
        source "${RECONFIG_DIR}/fabric-virtual-env/bin/activate"
        echo "  * Installing fabric int '${RECONFIG_DIR}/fabric-virtual-env'..."
        pip install fabric
    else
        echo "Attempting to use existing fabric installation found in '${RECONFIG_DIR}/fabric-virtual-env'"
        source "${RECONFIG_DIR}/fabric-virtual-env/bin/activate"
    fi
fi

echo "  * Re-checking if fabric module is now available in python environment..."
if ! python -c 'import fabric' >/dev/null 2>&1; then
    echo "  * Could not successfully install fabric into python environemnt." >&2
else
    echo "  * Fabric installed successfully into python environment"
fi

### If we get this far, all our preflight checks have passed, so now on to business...
echo "  * All preflight checks passed in '$(basename "${0}")'."

# Merges mozharness, buildbot-configs from default -> production.
# Merges buildbostcustom from default -> production-0.8.
# Returns 0 if something got merged, otherwise returns 1.
function merge_to_production {
    [ "${MERGE_TO_PRODUCTION}" == 0 ] && return 0
    for repo in mozharness buildbot-configs buildbotcustom; do
        if [ -d "${RECONFIG_DIR}/${repo}" ]; then
            echo "  * Existing hg clone of ${repo} found: '${RECONFIG_DIR}/${repo}' - skipping"
            continue
        fi
        echo "  * Cloning ssh://hg.mozilla.org/build/${repo} into '${RECONFIG_DIR}/${repo}'..."
        hg clone "ssh://hg.mozilla.org/build/${repo}" "${RECONFIG_DIR}/${repo}"
        hg -R "${RECONFIG_DIR}/${repo}" pull
        if [ "${repo}" == 'buildbotcustom' ]; then
            branch='production-0.8'
        else
            branch='production'
        fi
        echo "  * Merging ${repo} from default to ${branch}..."
        hg -R "${RECONFIG_DIR}/${repo}" up -r "${branch}"
        {
            echo "Merging from default"
            echo
            hg -R "${RECONFIG_DIR}/${repo}" merge -P default
        } > "${RECONFIG_DIR}/${repo}_preview_changes.txt"
        # Merging can fail if there are no changes between default and "${branch}"
        set +e
        hg -R "${RECONFIG_DIR}/${repo}" merge default
        RETVAL="${?}"
        if [ "${RETVAL}" == '255' ]; then
            echo "  * No changes found in ${repo} - skipping"
            continue
        elif [ "${RETVAL}" != '0' ]; then
            echo "  * An error occurred during hg merge (exit code was ${RETVAL}). Please resolve conflicts/issues in '${RECONFIG_DIR}/${repo}',"
            echo "    push to ${branch} branch, and run this script again." >&2
            exit 69
        fi
        echo "  * One or more changes merged successfully"
        set -e
        hg -R "${RECONFIG_DIR}/${repo}" commit -l "${RECONFIG_DIR}/${repo}_preview_changes.txt"
        if [ "${DRY_RUN}" == '0' ]; then
            echo "  * Pushing '${RECONFIG_DIR}/${repo}' ${branch} branch to ssh://hg.mozilla.org/build/${repo}..."
            hg -R "${RECONFIG_DIR}/${repo}" push
        fi
        touch "${RECONFIG_DIR}/merged_flag"
    done
    [ -f "${RECONFIG_DIR}/merged_flag" ] && return 0 || return 1
}

# Return code of merge_to_production is 0 if merge performed successfully and changes made
if ./merge_to_production.sh || [ "${FORCE_RECONFIG}" == '1' ]; then
    if [ "${USE_TMUX}" == '1' ]; then
        if "${DRY_RUN}" == '1' ]; then
            echo "  * Not running '$(pwd)/reconfig_tmux.sh' since this is a dry run"
        else
            echo "  * Running '$(pwd)/reconfig_tmux.sh'..."
	        ./reconfig_tmux.sh -f
	    fi
    else
        if "${DRY_RUN}" == '1' ]; then
            echo "  * Dry run; not running: '$(pwd)/manage_masters.py' -f '$(pwd)/production-masters.json' -j16 -R scheduler -R build -R try -R tests show_revisions update"
            echo "  * Dry run; not running: '$(pwd)/manage_masters.py' -f '$(pwd)/production-masters.json' -j32 -R scheduler -R build -R try -R checkconfig reconfig"
        else
            # Split into two steps so -j option can be varied between them
            echo "  * Running: '$(pwd)/manage_masters.py' -f '$(pwd)/production-masters.json' -j16 -R scheduler -R build -R try -R tests show_revisions update"
            ./manage_masters.py -f production-masters.json -j16 -R scheduler -R build -R try -R tests show_revisions update
            echo "  * Running: '$(pwd)/manage_masters.py' -f '$(pwd)/production-masters.json' -j32 -R scheduler -R build -R try -R checkconfig reconfig"
            ./manage_masters.py -f production-masters.json -j32 -R scheduler -R build -R try -R checkconfig reconfig
        fi
    fi
fi

if [ "${UPDATE_WIKI}" == "1" ]; then
    {
        echo '|-'
        echo '| in production'
        echo "| `TZ=America/Los_Angeles date +"%Y-%m-%d %H:%M PT"`"
        echo '|'
    } > "${RECONFIG_DIR}/reconfig_update_for_maintenance.wiki"
    grep summary "${RECONFIG_DIR}"/*_preview_changes.txt | \
        awk '{sub (/ r=.*$/,"");print substr($0, index($0,$2))}' | \
        sed 's/[Bb]ug \([0-9]*\):* *-* */\* {{bug|\1}} - /' | \
        sed 's/^[ \t]*//;s/[ \t,;]*$//' | \
        sed 's/^\([^\*]\)/\* \1/' | \
        sort -u >> "${RECONFIG_DIR}/reconfig_update_for_maintenance.wiki"
    ./update_maintenance_wiki.sh "${RECONFIG_DIR}/reconfig_update_for_maintenance.wiki"
    rm "${RECONFIG_DIR}"/*_preview_changes.txt
fi

echo "  * Reconfig completed. Wiki markup (for changes only) in file '${RECONFIG_DIR}/reconfig_update_for_maintenance.wiki'."