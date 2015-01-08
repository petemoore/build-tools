#!/bin/bash -exv
[ -z "${1}" ] || [ -z "${2}" ] && exit 1
TOX_INI_DIR="${1}"
TOX_WORK_DIR="${2}"

function hgme {
    repo="${1}"
    if [ ! -d "${TOX_WORK_DIR}/${repo}" ]; then
        hg clone https://hg.mozilla.org/build/${repo} "${TOX_WORK_DIR}/${repo}"
    else
        # this is equivalent to hg purge but doesn't require the hg purge plugin to be enabled
        hg status -un0 -R "${TOX_WORK_DIR}/${repo}" | xargs rm -rf
        hg pull -u -R "${TOX_WORK_DIR}/${repo}"
    fi
}

hgme buildbot
hgme buildbotcustom
hgme buildbot-configs

hg -R "${TOX_WORK_DIR}/buildbot" checkout production-0.8
hg -R "${TOX_WORK_DIR}/buildbotcustom" checkout production-0.8
hg -R "${TOX_WORK_DIR}/buildbot-configs" checkout production
cd "${TOX_WORK_DIR}/buildbot/master" && python setup.py install
cd "${TOX_WORK_DIR}/buildbot-configs" && python setup.py install
rm -rf "${TOX_INI_DIR}/test-output"
rm -rf "${TOX_INI_DIR}/run/shm/buildbot"
mkdir -p "${TOX_INI_DIR}/run/shm/buildbot"
cd "${TOX_WORK_DIR}/buildbot-configs"
./test-masters.sh -e
