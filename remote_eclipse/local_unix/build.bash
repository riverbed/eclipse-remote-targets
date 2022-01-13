#! /bin/bash
#
# build.bash -- wrapper to launch build.sh
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
    PATH="$REMOTE_ECLIPSE_DIR/local_unix:$PATH"
}
setPath
source bash-config.bash
local_error_filter build.sh "$@"
