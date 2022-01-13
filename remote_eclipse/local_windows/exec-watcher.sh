#! /bin/bash
#
# exec-watcher.sh -- wrapper to watch running executions
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

trap handle_interrupt SIGINT

# Use a single file for debugging that you can tail -f to see
export EWDEBUG_OUTPUT_FILE="$HOME/Desktop/exec-watcher-log.txt"

if [[ -e "$EWDEBUG_OUTPUT_FILE" ]]; then
    ewdebug_echo()
    {
        echo "$@" | unix2platform >> "$EWDEBUG_OUTPUT_FILE"
    }
    
    ewdebug_cat()
    {
        cat "$@" | unix2platform >> "$EWDEBUG_OUTPUT_FILE"
    }
else
    ewdebug_echo()
    {
         return
    }
    ewdebug_cat()
    {
         return
    }
fi

handle_interrupt()
{
    ewdebug_echo "** $(date): Trapped SIGINT"
}

wait_for_pids_exit()
{
    local pid1=$1
    shift

    if [[ -z "$pid1" ]]; then
        exit_with_error "$FUNCNAME: Must supply pid."
    fi
    
    local pid2=$1
    shift

    if [[ -z "$pid2" ]]; then
        exit_with_error "$FUNCNAME: Must supply pid."
    fi
    
    ewdebug_echo "Waiting for PIDs $pid1 or $pid2 to finish ..."
    ewdebug_echo "${FUNCNAME[0]}() pid=$$"
    while [[ true ]]; do
        ps > "$PSFILE"
        ewdebug_echo
        ewdebug_cat "$PSFILE"
        local ps_result1=$( sed -n "\\#^[ ]*$pid1[ ]#p" "$PSFILE" )
        local ps_result2=$( sed -n "\\#^[ ]*$pid2[ ]#p" "$PSFILE" )
        if [[ -z "${ps_result1}" ]] || [[ -z "${ps_result2}" ]]; then
            break
        fi
        sleep 0.5
    done
}

main()
{
    ewdebug_echo "Entering ${FUNCNAME[0]}() pid=$$"
    export MY_SSH_PID=$1
    ewdebug_echo "MY_SSH_PID is ${MY_SSH_PID}"

    PSFILE="$TMPDIR/pid$$-ps.txt"
    ewdebug_echo "TMPDIR is $TMPDIR."

    ps > "$PSFILE"
    local sedex="s#^ *${MY_SSH_PID}  *[0-9][0-9]*  *\\([0-9][0-9]*\\).*#\\1#p"
    local pgid=$(sed -n "${sedex}" "$PSFILE")
    if [[ -n "$pgid" ]]; then
        ewdebug_echo "Waiting for $pgid or ${MY_SSH_PID} to finish ..."
        wait_for_pids_exit $pgid ${MY_SSH_PID}
    
        pgid=$(sed -n "${sedex}" "$PSFILE")

        if [[ -n "$pgid" ]]; then
            ewdebug_echo "Terminating parent PID $PPID ..."
            kill -SIGTERM $PPID >& /dev/null
            ewdebug_echo "Killing the SSH pid ${MY_SSH_PID}"
            kill -SIGTERM ${MY_SSH_PID} >& /dev/null
        else
            ewdebug_echo "SSH PID ${MY_SSH_PID} exited after waiting"
        fi
        ps > "$PSFILE"
        ewdebug_echo
        ewdebug_cat "$PSFILE"
        
        pgid=$(sed -n "${sedex}" "$PSFILE")
        if [[ -n "$pgid" ]]; then
            ewdebug_echo "Attempt to kill the SSH pid ${MY_SSH_PID} FAILED."
            ewdebug_echo
            ewdebug_echo "Force killing the SSH pid ${MY_SSH_PID}."
            kill -9 ${MY_SSH_PID} >& /dev/null
            ps > "$PSFILE"
            ewdebug_echo
            ewdebug_cat "$PSFILE"
        fi
    else
        ewdebug_echo "SSH PID ${MY_SSH_PID} has already exited before waiting"
    fi
    ewdebug_echo
    ewdebug_echo "Leaving ${FUNCNAME[0]}() pid=$$"
    rm -f "$PSFILE" >& /dev/null
}

main "$@"

