#! /bin/bash
#
# makePlatformPrivateKey.sh -- No-OP, don't need a PuTTY format key in Unix.
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

echo "NO-OP" > /dev/null
status=$?
if [[ $status != 0 ]]; then
    exit
fi
