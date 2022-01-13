#
# sigwrap_setup.py -- Setup for signal handling wrapper process
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

from distutils.core import setup
import py2exe

setup(console=['sigwrap.py'])