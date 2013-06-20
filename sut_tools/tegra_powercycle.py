#!/usr/bin/env python

#
# Assumes Python 2.6
#

import os
import sys

sys.path.append(os.path.join(os.path.dirname(__file__), "../lib/python"))

import sut_lib.powermanagement as powermanagement

if len(powermanagement.tegras) == 0:
    print "error: The devices.json data file appears to be empty or not found."
    sys.exit(2)

if len(sys.argv[1:]) == 0:
    print "usage: %s [tegra-]### [...]" % sys.argv[0]
    sys.exit(1)

for tegra in sys.argv[1:]:
    if not tegra.lower().startswith('tegra-'):
        tegra = 'tegra-%s' % tegra
    if not tegra in powermanagement.tegras:
        print "ERROR: %s not found in devices.json" % tegra

    powermanagement.reboot_device(tegra, debug=True)
