#! /bin/bash
#
# launch.sh -- Launch a file on a Unix platform (FreeBSD, Linux, etc.)
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

if which gnumeric >& /dev/null; then
    gnumeric "$@" &
elif which $EDITOR >& /dev/null; then
    $EDITOR "$@" &
else
    echo "Cannot launch, no spreadsheet or editor found." 1>&2
fi