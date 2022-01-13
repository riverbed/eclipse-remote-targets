#! /bin/bash
#
# remote-action.bash -- wrapper to launch all-unix remote-action.cmd
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export PLAT_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/bin && pwd)"
"$REMOTE_ECLIPSE_LOC/local_unix/remote-action.cmd" "$@"