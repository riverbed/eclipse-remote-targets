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

setPath ()
{
    local REMOTE_ECLIPSE="$(cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd)"
    export PATH="$REMOTE_ECLIPSE/remote_unix/local_shared:$PATH"
    export PATH="$REMOTE_ECLIPSE/local_common:$PATH"
    export PATH="$REMOTE_ECLIPSE/local_unix:$PATH"
}
setPath
source bash-config.bash
source remote-gdb.sh "$@"
