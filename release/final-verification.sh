#!/bin/bash

# In the updates subdirectory of the directory this script is in,
# there are a bunch of config files. You should call this script,
# passing the names of one or more of those files as parameters
# to this script.
#
# This script will then cat all of the config files specified,
# replacing the first instance in any line of 'betatest' or
# 'esrtest' with 'releasetest', and place the generated output
# into a temporary file. Then it will call:
#
#     verify.sh -t <the generated temporary file>
#
# The output from this script will be logged into another
# temporary file, which is then grep'd to see what was
# successful and what was not.

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "${0}") [list of update verify configs]" >&2
    # distinct exit code of 127 for this exception
    exit 127
fi

# make 'configs' an array, in case any argument contains e.g. whitespace
configs=("${@}")

# move into updates subdirectory of the directory this script is in
cd "$(dirname "${0}")/updates"

# generate temporary files in case two instances of this script are running
# concurrently...
UPDATE_CFG="$(mktemp -t update.cfg.XXXXXX)"
QUICK_VERIFY_LOG="$(mktemp -t quickVerify.log.XXXXXX)"

# this version of the sed expression works on mac and linux
cat "${configs[@]}" | sed 's/betatest/releasetest/;s/esrtest/releasetest/' > "${UPDATE_CFG}"
./verify.sh -t "${UPDATE_CFG}" 2>&1 | tee "${QUICK_VERIFY_LOG}"
rm "${UPDATE_CFG}"

# this command's exit status will be 0 regardless of whether it passed or failed
# we grep the log so we can inform buildbot correctly
if grep HTTP/ "${QUICK_VERIFY_LOG}" | grep -v 200 | grep -qv 302; then
    # One or more links failed
    # distinct exit code of 2 for this exception
    rm "${QUICK_VERIFY_LOG}"
    exit 2
elif grep '^FAIL' "${QUICK_VERIFY_LOG}"; then
    # Usually this means that we got an empty update.xml
    # distinct exit code of 1 for this exception
    rm "${QUICK_VERIFY_LOG}"
    exit 1
else
    # Everything passed
    rm "${QUICK_VERIFY_LOG}"
    exit 0
fi
