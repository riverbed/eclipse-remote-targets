#! /bin/bash
#
# remote-gdb.bash -- wrapper to launch windows remote-gdb.bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

REMOTE_ECLIPSE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]//\\//}")"/../../ && pwd)"
REMOTE_ECLIPSE_LOC="$(cd "$(dirname "${BASH_SOURCE[0]//\\//}")"/../../ && pwd -W)"
REMOTE_ECLIPSE_LOC="$(echo ${REMOTE_ECLIPSE_LOC:0:1} | tr '[a-z]' '[A-Z]')${REMOTE_ECLIPSE_LOC:1}"
REMOTE_ECLIPSE_LOC="${REMOTE_ECLIPSE_LOC//\//\\}"

sc="export REMOTE_ECLIPSE_PATH='$REMOTE_ECLIPSE_PATH'"
sc="$sc; source '$REMOTE_ECLIPSE_PATH/local_windows/remote-gdb.bash'"

for arg in "$@"; do
    sc="$sc '${arg//\\//}'"
done

eval "$sc"