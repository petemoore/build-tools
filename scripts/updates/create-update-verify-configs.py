#!/usr/bin/env python

import site
import sys
import os
from os import path

site.addsitedir(path.join(path.dirname(__file__), "../../lib/python"))
site.addsitedir(path.join(path.dirname(__file__), "../../lib/python/vendor"))

from distutils.version import LooseVersion
from release.updates.patcher import PatcherConfig
from release.l10n import makeReleaseRepackUrls
from release.platforms import buildbot2updatePlatforms, buildbot2ftp
from release.paths import makeReleasesDir, makeCandidatesDir
from release.info import readReleaseConfig
from util.retry import retry
from util.hg import mercurial, make_hg_url, update
from release.updates.verify import UpdateVerifyConfig


HG = "hg.mozilla.org"
DEFAULT_BUILDBOT_CONFIGS_REPO = make_hg_url(HG, 'build/buildbot-configs')
DEFAULT_MAX_PUSH_ATTEMPTS = 10
REQUIRED_CONFIG = ('productName', 'buildNumber', 'ausServerUrl',
                   'stagingServer')
FTP_SERVER_TEMPLATE = 'http://%s/pub/mozilla.org'


def validate(options):
    err = False
    config = {}

    if not path.exists(path.join('buildbot-configs', options.release_config)):
        print "%s does not exist!" % options.release_config
        sys.exit(1)

    config = readReleaseConfig(path.join('buildbot-configs',
                                         options.release_config))
    for key in REQUIRED_CONFIG:
        if key not in config:
            err = True
            print "Required item missing in config: %s" % key

    if err:
        sys.exit(1)
    return config


if __name__ == "__main__":
    from optparse import OptionParser
    parser = OptionParser("")

    parser.add_option("-c", "--config", dest="config")
    parser.add_option("--platform", dest="platform")
    parser.add_option("-r", "--release-config-file", dest="release_config",
                      help="The release config file to use.")
    parser.add_option("-b", "--buildbot-configs", dest="buildbot_configs",
                      help="The place to clone buildbot-configs from",
                      default=os.environ.get('BUILDBOT_CONFIGS_REPO',
                                             DEFAULT_BUILDBOT_CONFIGS_REPO))
    parser.add_option("-t", "--release-tag", dest="release_tag",
                      help="Release tag to update buildbot-configs to")
    parser.add_option("--channel", dest="channel", default="betatest")
    parser.add_option("--full-check-locale", dest="full_check_locales",
                      action="append", default=['de', 'en-US', 'ru'])
    parser.add_option("--output", dest="output")

    options, args = parser.parse_args()

    required_options = ['config', 'platform', 'release_config',
                        'buildbot_configs', 'release_tag']
    options_dict = vars(options)
    for opt in required_options:
        if not options_dict[opt]:
            print >> sys.stderr, "Required option %s not present" % opt
            sys.exit(1)

    update_platform = buildbot2updatePlatforms(options.platform)[-1]
    ftp_platform = buildbot2ftp(options.platform)
    full_check_locales = options.full_check_locales

    # Variables from release config
    retry(mercurial, args=(options.buildbot_configs, 'buildbot-configs'))
    update('buildbot-configs', revision=options.release_tag)
    release_config = validate(options)
    product_name = release_config['productName']
    staging_server = FTP_SERVER_TEMPLATE % release_config['stagingServer']
    aus_server_url = release_config['ausServerUrl']
    build_number = release_config['buildNumber']
    previous_releases_staging_server = FTP_SERVER_TEMPLATE % \
        release_config.get('previousReleasesStagingServer',
                           release_config['stagingServer'])

    # Current version data
    pc = PatcherConfig(open(options.config).read())
    app_name = pc['appName']
    to_version = pc['current-update']['to']
    to_ = makeReleaseRepackUrls(
        product_name, app_name, to_version, options.platform,
        locale='%locale%', signed=True, exclude_secondary=True
    ).values()[0]
    candidates_dir = makeCandidatesDir(
        product_name, to_version, build_number, ftp_root='/')
    to_path = "%s%s" % (candidates_dir, to_)

    partials = pc['current-update']['partials'].keys()
    # Exclude current version from update verify
    completes = [c for c in pc['release'].keys() if c != to_version]

    uvc = UpdateVerifyConfig(product=app_name, platform=update_platform,
                             channel=options.channel,
                             aus_server=aus_server_url, to=to_path)

    for v in reversed(sorted(completes, key=LooseVersion)):
        appVersion = pc['release'][v]['extension-version']
        build_id = pc['release'][v]['platforms'][ftp_platform]
        locales = pc['release'][v]['locales']
        # remove exceptions, e.g. "ja" form mac
        for locale, platforms in pc['release'][v]['exceptions'].iteritems():
            if ftp_platform not in platforms:
                locales.remove(locale)
        # Exclude locales being full checked
        quick_check_locales = [l for l in locales
                               if l not in full_check_locales]

        from_ = makeReleaseRepackUrls(
            product_name, app_name, v, options.platform,
            locale='%locale%', signed=True, exclude_secondary=True
        ).values()[0]
        release_dir = makeReleasesDir(product_name, v, ftp_root='/')
        from_path = "%s%s" % (release_dir, from_)

        if v in partials:
            # Full test for all locales
            # "from" and "to" to be downloaded from the same staging
            # server in dev environment
            uvc.addRelease(release=appVersion, build_id=build_id,
                           locales=locales,
                           patch_types=['complete', 'partial'],
                           from_path=from_path, ftp_server_from=staging_server,
                           ftp_server_to=staging_server)
        else:
            # Full test for limited locales
            # "from" and "to" to be downloaded from different staging
            # server in dev environment
            uvc.addRelease(release=appVersion, build_id=build_id,
                           locales=full_check_locales, from_path=from_path,
                           ftp_server_from=previous_releases_staging_server,
                           ftp_server_to=staging_server)
            # Quick test for other locales, no download
            uvc.addRelease(release=appVersion, build_id=build_id,
                           locales=quick_check_locales)
    f = open(options.output, 'w')
    uvc.write(f)