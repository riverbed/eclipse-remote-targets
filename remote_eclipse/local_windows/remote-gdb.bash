#! /bin/bash
#
# remote-gdb.bash -- wrapper to launch common remote-gdb.sh
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export WORKSPACE_LOC="$WorkspaceDirPath"

# For older versions of git bash, the variable names are all
# caps, and thus we need to check for those too
if [[ -n "$WORKSPACEDIRPATH" ]]; then
    export WORKSPACE_LOC="$WORKSPACEDIRPATH"
fi

setPath ()
{
    local REMOTE_ECLIPSE="$(cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd)"
    export PATH="$REMOTE_ECLIPSE/remote_unix/local_shared:$PATH"
    export PATH="$REMOTE_ECLIPSE/local_common:$PATH"
    export PATH="$REMOTE_ECLIPSE/local_windows:$PATH"
}
setPath
source bash-config.bash
# Disable the ssh wrapper (set up above in bash-config.bash) for gdb
unset -f ssh
source remote-gdb.sh "$@"
