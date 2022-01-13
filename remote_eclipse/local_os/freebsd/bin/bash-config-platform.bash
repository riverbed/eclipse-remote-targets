#!/bin/bash
#
# bash-config-platform.bash -- FreeBSD specific configuration options
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export LINEBUFSEDSWITCH=-l
export GDB_DSF_USE_TTY=false
export PLATFORM_XTERM_BIN=/usr/local/bin/xterm
export PLATFORM_XTERM_POST_RUN_ACTION=":"

function get_md5()
{
    md5 -q "$@"
}
export -f get_md5

process_grep()
{
    # For FreeBSD, you call ps -ax (- required)
    ps -o pid,ppid,command -ax | grep -v grep | \
        grep -e "$1" | awk '{ print $1 }' | xargs
}
export -f process_grep
