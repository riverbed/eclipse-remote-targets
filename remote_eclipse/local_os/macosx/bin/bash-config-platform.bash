#!/bin/bash
#
# bash-config-platform.bash -- Mac OS X specific configuration options
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export LINEBUFSEDSWITCH=-l
export GDB_DSF_USE_TTY=true
export PLATFORM_XTERM_BIN=/usr/X11/bin/xterm
export PLATFORM_XTERM_POST_RUN_ACTION="if [[ \$(ps -ax | grep -v grep | grep -c xterm) == 0 ]]; then osascript -e 'tell application \"XQuartz\" to quit'; fi"

# Try a few known locations: if we don't find it, it will say not found
if [[ -e ${PLATFORM_XTERM_BIN} ]]; then
    : # Do nothing, found it
elif [[ -e /opt/X11/bin/xterm ]]; then
    PLATFORM_XTERM_BIN=/opt/X11/bin/xterm
elif [[ -e /usr/X11R6/bin/xterm ]]; then
    PLATFORM_XTERM_BIN=/usr/X11R6/bin/xterm
fi

function get_md5()
{
    md5 -q "$@"
}
export -f get_md5

process_grep()
{
    # For Mac OS X, you call ps -ax (- required)
    ps -o pid,ppid,command -ax | grep -v grep | \
        grep -e "$1" | awk '{ print $1 }' | xargs
}
export -f process_grep
