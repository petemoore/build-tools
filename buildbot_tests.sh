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
rm -rf "${TOX_WORK_DIR}/buildbot-configs/test-output"
rm -rf "${TOX_WORK_DIR}/buildbot-configs/run/shm/buildbot"
mkdir -p "${TOX_WORK_DIR}/buildbot-configs/run/shm/buildbot"
cd "${TOX_WORK_DIR}/buildbot-configs"
set +exv
./test-masters.sh -e
echo "PYTHONPATH: '${PYTHONPATH}'"
find "${TOX_WORK_DIR}/buildbot-configs/test-output" -name '*.log' | while read file; do
    echo "${file}"
    echo "${file//?/#}"
    cat "${file}"
    echo
done
pip freeze
ls -l "${TOX_WORK_DIR}/py27-hg2.6/lib/python2.7/site-packages"
