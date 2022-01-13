#! /bin/bash
#
# setup-project.cmd -- wrapper to launch all-unix setup-project.bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export PLAT_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/bin && pwd)"
cd "$REMOTE_ECLIPSE_LOC/local_unix"
./setup-project.bash "$@"
