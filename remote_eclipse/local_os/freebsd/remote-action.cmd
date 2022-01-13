#! /bin/bash
#
# remote-action.cmd -- wrapper to launch all-unix remote-action.cmd
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export PLAT_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/bin && pwd)"
export REMOTE_ACTION_PPID=$$
trap on_exit EXIT
on_exit()
{
    # On FreeBSD use ps -ax with dash
    local child_pids=$(ps -o pid,command -ax | grep -v grep | \
        grep " REMOTE_ACTION_PPID=$REMOTE_ACTION_PPID;" | \
        awk '{ print $1 }' | xargs)

    if [[ -n "$child_pids" ]]; then
        kill -TERM $child_pids >& /dev/null
    fi
}
"$REMOTE_ECLIPSE_LOC/local_unix/remote-action.cmd" "$@"