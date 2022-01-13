#!/bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

trap cleanup SIGINT SIGTERM EXIT

export DEBUG_OUTPUT_FILE="$HOME/Desktop/gdb-debug.txt"

cleanup()
{
    if [[ -n ${RESUME_PID} ]]; then
        toRemove=$RESUME_PID
        RESUME_PID=
        kill $toRemove
        wait $toRemove
    fi
    rm -f "$DEBUG_OUTPUT_FILE"
}

do_tail()
{
    cleanup
    touch "$DEBUG_OUTPUT_FILE"
    clear
    echo "============================================================================"
    echo "                Watching Remote GDB Output (Ctrl-C to break)                "
    echo "============================================================================"

    tail -f "$DEBUG_OUTPUT_FILE" &
    RESUME_PID=$!
    wait $RESUME_PID
    RESUME_PID=
    cleanup
}

do_tail "$@"