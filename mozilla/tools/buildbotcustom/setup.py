#!/usr/bin/env python

from distutils.core import setup

setup(name='buildbotcustom',
      version='0.2',
      description='Mozilla custom buildbot infrastructure',
      author='Axel Hecht',
      author_email='l10n@mozilla.com',
      packages=['buildbotcustom','buildbotcustom.changes','buildbotcustom.steps','buildbotcustom.slave','buildbotcustom.status','buildbotcustom.builds'],
      package_data={'buildbotcustom.status': ['*.mako']}
     )
