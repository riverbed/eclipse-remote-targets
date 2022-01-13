#! /bin/bash
#
# setup-project.bash -- wrapper to launch setup-project.sh
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

setPath ()
{
    local REMOTE_ECLIPSE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
    PATH="$REMOTE_ECLIPSE_DIR/remote_unix/local_shared:$PATH"
    PATH="$REMOTE_ECLIPSE_DIR/local_common:$PATH"
    PATH="$REMOTE_ECLIPSE_DIR/local_windows:$PATH"
}
list_all_functions()
{
    : # Will be overridden
}
export -f list_all_functions
setPath
source bash-config.bash
launch_xterm -title "Setup a Remote Project" setup-project.sh "$@"
if [[ $? == 2 ]]; then
    pause
fi
