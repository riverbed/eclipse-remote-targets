#!/bin/bash
#
# bash-config-platform.bash -- Linux specific configuration options
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export LINEBUFSEDSWITCH=-u
export GDB_DSF_USE_TTY=true
export PLATFORM_XTERM_BIN=/usr/bin/xterm
export PLATFORM_XTERM_POST_RUN_ACTION=":"

function get_md5()
{
    md5sum "$@" | sed 's/\([0-9a-f]*\) .*/\1/'
}
export -f get_md5

process_grep()
{
    # For linux, it is ps ax (no dash)
    ps -o pid,ppid,command ax | grep -v grep | \
        grep -e "$1" | awk '{ print $1 }' | xargs
}
export -f process_grep
