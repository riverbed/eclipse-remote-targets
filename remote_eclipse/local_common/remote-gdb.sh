#! /bin/bash
#
# remote-gdb.sh -- Remote GDB launcher
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# Header files
source common-functions.sh

# Signals used for communicating with the pause handler
export REMOTE_GDB_FOUND_REMOTE_PID_STATUS=33

# Set traps for control c, termination, and cleanup
trap on_interrupt SIGINT
trap on_termination SIGTERM
trap on_exit EXIT

# Enable job control
set -m

# Use a single file for debugging that you can tail -f to see
export DEBUG_OUTPUT_FILE="$HOME/Desktop/gdb-debug.txt"

if [[ -e "$DEBUG_OUTPUT_FILE" ]]; then
    debug_echo()
    {
        echo "$@" | unix2platform >> $DEBUG_OUTPUT_FILE
    }
else
    debug_echo()
    {
         return 
    }
fi

on_interrupt()
{
    debug_echo "Received the SIGINT signal."
    send_remote_signal SIGINT
    DO_CONTINUE=true
}

on_termination()
{
    if [[ -e "${LOOP_PID_FILE}" ]]; then
        local raisedSignal="$(< "${LOOP_PID_FILE}")"
        if [[ "$raisedSignal" == "TTYTERM" ]]; then
            RAISED_SIGNAL=$raisedSignal
        fi
     fi

    debug_echo "Received the SIGTERM signal, RAISED_SIGNAL=${RAISED_SIGNAL}"
    if [[ -e "$ACTUAL_SSH_STATUS_FILE" ]]; then
        export ACTUAL_SSH_STATUS="$(< "$ACTUAL_SSH_STATUS_FILE")"
        rm -f "$ACTUAL_SSH_STATUS_FILE"
    fi
    if [[ "${RAISED_SIGNAL}" == "TTYTERM" ]]; then
        cleanup
        RAISED_SIGNAL=SIGTERM
        DO_CONTINUE=false
    else
        send_remote_signal SIGTERM
        cleanup
        if [[ $GDB_DSF_USE_TTY == false ]]; then
            # We have no TTY to watch termination, so break loop to exit
            RAISED_SIGNAL=SIGTERM
            DO_CONTINUE=false
        else
            DO_CONTINUE=true
        fi
    fi
}

on_exit()
{
    cleanup
}

cleanup()
{
    debug_echo "Cleanup files on exit."
    rm -f "$OUTPUT_TTY_FILE" "$REMOTE_PID_FILE" "$LOOP_PID_FILE" "$ACTUAL_SSH_STATUS_FILE" "$ACTUAL_SSH_PID_FILE"
}

add_remote_environment_exec()
{
    : # Used by extensions for particular modules (is overriden)
}

debug_args()
{
    echo "args: $@" >> $DEBUG_OUTPUT_FILE
    echo "PROJECT_NAME: $PROJECT_NAME" >> $DEBUG_OUTPUT_FILE
    let i=0
    while [[ -n "$1" ]]; do
        let i=$i+1
        echo "arg $i is [$1]" >> $DEBUG_OUTPUT_FILE
        shift
    done
    echo "argsdos: $argsdos" >> $DEBUG_OUTPUT_FILE
    unix2platform $DEBUG_OUTPUT_FILE >& /dev/null
}

translateGdbOptions()
{
    DUMMYCOREFILE=
    OPTIONS=
    until [[ -z "$1" ]]; do
        local value="$1"
        local parameter=
        local prevalue=
        if [[ "${1:0:2}" = "--" ]]; then
            tmp=${1:2}               # Strip off leading '--'
            if [[ "$tmp" != "${tmp/=/}" ]]; then # Has = ?
                parameter=${tmp%%=*} # Extract name.
                value=${tmp##*=}           # Extract value.
                prevalue="--$parameter="
            fi
        fi
        shift
        if [[ "$value" == "-c" ]]; then
            DUMMYCOREFILE="$1"
            shift
            debug_echo "Skipping corefile parameter"
            continue
        fi
        if [[ "${value:0:1}" == "/" ]]; then
            #Absolute path, convert the drive letter
            if [[ "$parameter" == "cd" ]]; then
                value="$RWSDIR/$PROJECT_NAME"
            elif [[ -z "$parameter" ]]; then
                # No parameter but as a file, so must be the binary to run
                if [[ -z "$DUMMYCOREFILE" ]]; then
                    value="$bintorun"
                else
                    # Skip the value, if it is a core dump
                    continue
                fi
            fi
        fi
        if [[ "${value}" == "-tty" ]]; then
            # Don't pass on the -tty parameter
            continue
        fi
        if [[ "${value}" != "${value/ /}" ]]; then
            # Has spaces? wrap it with quotes
            value="\"${value}\""
        fi
        OPTIONS="$OPTIONS $prevalue$value"
    done
    OPTIONS="${OPTIONS:1}"
}

remote_gdb_common_get_binary()
{
    debug_echo "PROJECT_PATH is $PROJECT_PATH"

    cd "$PROJECT_PATH"

    universal_local_config

    debug_echo "MAINBINPATH is $MAINBINPATH"
    debug_echo "SUBPROJECT is $SUBPROJECT"
    debug_echo "MAINBINARY is $MAINBINARY"
    debug_echo "REMOTEPROJECTDIR is $REMOTEPROJECTDIR"

    remoteuser="$REMOTEBUILDUSER"
    remotehost="$REMOTEBUILDHOST"

    if [[ -z "$remoteuser" ]] || [[ -z "$remotehost" ]]; then
        show_error "No remote user or host specified," \
             "try building first."
        exit 1
    fi
}

remote_gdb_common_get_exec_settings()
{
    local SUBPROJECTDIR="$REMOTEPROJECTDIR/$SUBPROJECT"

    # If there is no working directy, run from the sub-project directory.
    if [[ -z "$EXECWD" ]]; then
        EXECWD="$SUBPROJECTDIR"
    elif [[ "${EXECWD:0:1}" != "/" ]]; then
        EXECWD="$SUBPROJECTDIR/${EXECWD%./}"
    fi

    if [[ -z "$BINALIAS" ]]; then
        BINALIAS="$MAINBINARY"
    fi

    bintorun="$SUBPROJECTDIR/$MAINBINPATH/$BINALIAS"

    debug_echo "bintorun is $bintorun"
}

getFreeBSDPidList()
{
    local remoteuser=$1
    local remotehost=$2
    local binarypattern=$3
    local getpidsc="ps -axwwo pid,user,command"
    getpidsc="${getpidsc} | egrep \"${binarypattern//\\/\\\\}\""
    getpidsc="${getpidsc} | egrep -v \"bash -c | egrep | /bin/sh \""

    debug_echo "STARTING SSH TO GET PROCESS LIST  ======"
    ssh -C "$remoteuser@$remotehost" "bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$getpidsc'" | getFreeBSDPidListInnerLoop
    debug_echo "FINISHED SSH TO GET PROCESS LIST ======"
}

getFreeBSDPidListInnerLoop()
{
    local pidLine=
    local leadingComma=""
    while read pidLine; do
        # Get first column (pid)
        local processId="${pidLine%% *}"
        # Strip first column from the line
        pidLine="${pidLine#* }"
        # Get 2nd column (user)
        local processUser="${pidLine%% *}"
        # Strip off the second column, now we have the description
        local processDesc="${pidLine#* }"
        echo -n "${leadingComma}{id=\"${processId}\",type=\"process\",description=\"${processDesc}\",user=\"${processUser}\"}"
        leadingComma=","
        debug_echo "pidLine is '$pidLine'"
    done
    # Print the end of line after looping over all processes
    echo
}

send_remote_signal()
{
    # The first time we need to 
    if [[ -z "${REMOTE_PID}" ]]; then
        if [[ -e "${REMOTE_PID_FILE}" ]]; then
            REMOTE_PID="$(< "${REMOTE_PID_FILE}")"
            rm -f "${REMOTE_PID_FILE}"
        fi
        
        # Now we've gotten it from the file.  It better not be blank
        if [[ -z "${REMOTE_PID}" ]]; then
            debug_echo "No remote PID detected."
        fi
    fi
    # We have already detected the exact REMOTE PID, use it
    debug_echo "Sending remote signal $1 to PID ${REMOTE_PID}"
    ssh "$remoteuser@$remotehost" "bash -c 'kill -s $1 ${REMOTE_PID}' >& /dev/null" &
}

getTtyName()
{
    local loopPid=$$
    echo $loopPid > "${LOOP_PID_FILE}"
    debug_echo "loopPid is $loopPid"
    
    # For platforms that use an output TTY, let's pipe the input stream to
    # extract and find the tty being used.  Then place that TTY in a file so
    # that the output stream that wants to pipe to the terminal can use it
    if [[ $GDB_DSF_USE_TTY == true ]] && [[ $DSF_ATTACH == false ]]; then
        rm -f "$OUTPUT_TTY_FILE"
        tee >( sed $LINEBUFSEDSWITCH -n \
                    "/[-]inferior[-]tty[-]set [-][-]thread[-]group/p" | \
               sed $LINEBUFSEDSWITCH "s/.* [-][-]thread[-]group i1 \\(.*\\)/\\1/" \
               > "$OUTPUT_TTY_FILE" )
    else
        cat -u
    fi
}

cat_unbuffered_with_interrupt()
{
    local status=
    # If we are post mortem, there is no interrupt stuff to worry about.
    if [[ $DSF_POST_MORTEM == true ]]; then 
        cat -u
        status=$?
    else
        local remotePid=""
        # OK, now we are either running directly or in attach mode.  We want to
        # enable sending an interrupt signal to the REMOTE PID, resulting in suspending
        # (pausing) the process.  First we need to watch the output stream from gdb to
        # find the PID.  Once we find it, we can then enable passing signals to the child
        # process and start pausing the current binary.
        while true; do 
            remote_gdb_pause_handler "$remotePid"
            status=$?
            
            if     [[ $status == ${REMOTE_GDB_FOUND_REMOTE_PID_STATUS} ]] && \
                   [[ -e "${REMOTE_PID_FILE}" ]]; then
                # Next check if we found the remote PID, and if so let's save it.
                remotePid="$(< "${REMOTE_PID_FILE}")"
                debug_echo "$FUNCNAME: remotePid detected as ${remotePid}" 
            else
                # We exited either normally or with an unknwon error, let's just exit out
                # with that status code.
                break
            fi
        done
    fi
    # Return the status of the unbuffered cat.
    return $status
}

doTtyEmulation()
{
    # For platforms where the output is sent to a terminal, pipe our output to
    # a script that emulates the terminal
    if [[ $GDB_DSF_USE_TTY == true ]] && [[ $DSF_ATTACH == false ]]; then
        cat_unbuffered_with_interrupt $FUNCNAME | tee >( emulateTty > /dev/null )
    else
        cat_unbuffered_with_interrupt $FUNCNAME
    fi
}

emulateTty()
{
    # If we are emulating a terminal, we first need to find out what the
    # terminal is.  The input stream will have that information.  Once that
    # information is available, we can start streaming any output messages.
    OUTPUT_TTY=""
    while [[ -z "$OUTPUT_TTY" ]]; do
        if [[ -e "$OUTPUT_TTY_FILE" ]]; then
            OUTPUT_TTY="$(cat "$OUTPUT_TTY_FILE")"
        fi
        if [[ -z "$OUTPUT_TTY" ]]; then
            # If we don't know the output stream yet, keep waiting a little
            # more.
            sleep 0.1 &
            wait $!
        fi
    done

    debug_echo "OUTPUT_TTY is $OUTPUT_TTY"

    # Now OUTPUT_TTY contains the name of the stream that eclipse wants gdb
    # to use for output.  So, we'll take the output of GDB and get only the
    # lines starting with @, those are the output lines.  Then we strip off
    # the wrapping and send them to the output tty.
    tee >( watchTtyForTermination ) | sed $LINEBUFSEDSWITCH -n "/^@\"/p" | \
         sed $LINEBUFSEDSWITCH "s/^@\"\\(.*\\)\\\\n\"/\\1/" > "$OUTPUT_TTY"
}

watchTtyForTermination()
{
    local gdbMiLine=""
    local forceTerminationFlag=false
    local doTermination=false
    sed $LINEBUFSEDSWITCH -n "/^\*stopped,reason=\"/p;/^=thread-group-exited,id=\"i1\"/p" | \
    while read gdbMiLine; do
        if [[ $forceTerminationFlag == true ]]; then
            forceTerminationFlag=false
            doTermination=true
        fi
        if [[ "$gdbMiLine" != "${gdbMiLine/,reason=}" ]]; then
            # Detect the difference between normal and forced termination
            # based on whether we see an exit-code line.
            if [[ "$gdbMiLine" != "${gdbMiLine/reason=\"exited-normally\"}" ]]; then
                debug_echo "Normal Termination detected line='$gdbMiLine', PID $$"
                if [[ $doTermination == true ]]; then
                    debug_echo "Forced termination false alarm"
                    doTermination=false
                fi
            elif [[ "$gdbMiLine" != "${gdbMiLine/reason=\"exited\"}" ]]; then
                debug_echo "Abnormal Termination detected line='$gdbMiLine', PID $$"
                local ssh_pid=$(process_grep "LOCAL_MY_PID=$$;")
                debug_echo "Sending interrupt to ssh PID=${ssh_pid} ..."
                kill -INT $ssh_pid
                wait $ssh_pid >& /dev/null
                break
            else
                debug_echo "Not exiting line='$gdbMiLine', PID $$"
            fi
        elif [[ "${gdbMiLine%,exit-code=*}" == "=thread-group-exited,id=\"i1\"" ]]; then
            forceTerminationFlag=true
            debug_echo "Forced termination possibly detected line='$gdbMiLine', PID $$"
        else
            debug_echo "Thread-group exit, but with exit-code line='$gdbMiLine', PID $$"
        fi
        if [[ $doTermination == true ]]; then
            local ssh_pid=$(process_grep "LOCAL_MY_PID=$$;")
            debug_echo "Sending interrupt to ssh PID=${ssh_pid} ..."
            kill -INT $ssh_pid
            wait $ssh_pid >& /dev/null
            break
        fi
    done
    
    if [[ -z "${LOOP_PID}" ]]; then
        if [[ -e "${LOOP_PID_FILE}" ]]; then
            LOOP_PID="$(< "${LOOP_PID_FILE}")"
            rm -f "${LOOP_PID_FILE}"
        fi
        
        # Now we've gotten it from the file.  It better not be blank
        if [[ -z "${LOOP_PID}" ]]; then
            debug_echo "No resume PID detected."
        fi
    fi
    
    if [[ -n "${LOOP_PID}" ]]; then
        debug_echo "sending terminate to the LOOP_PID ${LOOP_PID}"
        echo TTYTERM > "$LOOP_PID_FILE"
        kill -TERM $LOOP_PID
    fi
}

on_found_remote_pid()
{
    local remotePid="$1"
    debug_echo "$FUNCNAME: Found remotePid ${remotePid}."
    
    # Write the remote pid we calculated to the file and exit so we can read it
    echo "$remotePid" > "${REMOTE_PID_FILE}"
    return ${REMOTE_GDB_FOUND_REMOTE_PID_STATUS}
}

look_for_pid_line()
{
    local line="$1"
    
    if [[ "$line" != "${line/=thread-group-started,id=\"i1\",pid=\"/}" ]]; then
        remotePid="${line#*,pid=\"}"
        # Make sure we stripped off everything up to the number:
        if [[ "$remotePid" != "$line" ]]; then
            # Strip off the final quote
            remotePid="${remotePid%\"}"
        else
            # Otherwise the pid is unknown (blank)
            remotePid=""
        fi
        # Now we found the remote PID.  Use the exit routine
        on_found_remote_pid "$remotePid"
    fi
}

cat_unbuffered_find_remote_pid()
{
    local line=
    local status=
    local remotePid=$1
    while IFS= read -r line; do
        echo "$line"
        # Look at each line till we find one that has the remote PID
        if [[ -z "$remotePid" ]]; then
            look_for_pid_line "$line"
            status=$?
            if [[ "$status" == "${REMOTE_GDB_FOUND_REMOTE_PID_STATUS}" ]]; then
                debug_echo "$FUNCNAME: We found the remote pid ..."
                return $status
            fi
        fi
    done
    status=$?
    # While emulating cat, did we have a partial line left? Write it out
    if [[ -n "$line" ]]; then
        echo -n "$line"
    fi
    return $status
}

remote_gdb_pause_handler()
{
    local remotePid=$1
    # Do whatever was passed as the argument
    if [[ -z "$remotePid" ]]; then
        debug_echo "Searching for remote pid..."
        cat_unbuffered_find_remote_pid $remotePid
    else
        debug_echo "Already found remote pid $remotePid, using cat -u."
        cat -u
    fi
}

doGdbVersionPass()
{
    ssh -C "$remoteuser@$remotehost" "bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$sc'" > \
        "$SUBPROJECT/$MAINBINPATH/tmpgdbverout"
    if [[ "$DSF_POST_MORTEM" == "true" ]]; then
        cat "$SUBPROJECT/$MAINBINPATH/tmpgdbverout" | grep "^~~" | \
            sed "s/^~~\\(.*\\)/\\1/" > \
            $SUBPROJECT/$MAINBINPATH/gdbinitpm
    fi
}

doGdbSsh()
{
    RAISED_SIGNAL=NONE
    local errorStatus=
    if [[ -n "$ox1" ]]; then
        getTtyName | \
        #     tee "$HOME/Desktop/input-pre.txt"  | \
        sed $LINEBUFSEDSWITCH -e "$ix"           | \
        #     tee "$HOME/Desktop/input-post.txt" | \
        doActualSsh "$@" | \
        #     tee "$HOME/Desktop/output-pre.txt" | \
        sed $LINEBUFSEDSWITCH -e "$oxp" | \
        sed $LINEBUFSEDSWITCH -e "$ox1" | \
        sed $LINEBUFSEDSWITCH -e "$ox2" | \
        sed $LINEBUFSEDSWITCH -e "$ox3" | \
        sed $LINEBUFSEDSWITCH -e "$ox4" | \
        #     tee "$HOME/Desktop/output-post.txt" \
        doTtyEmulation &
        local loopPid=$!
        while true; do
            debug_echo "Pre wait in loop..."
            DO_CONTINUE=false
            wait $loopPid
            errorStatus=$?
            debug_echo "Post wait in loop..."
            if [[ ${DO_CONTINUE} == true ]]; then
                debug_echo "Continuing loop..."
                continue
            fi
            break
        done
    else
        #     tee "$HOME/Desktop/input-pre.txt"  | \
        sed $LINEBUFSEDSWITCH -e "$ix"           | \
        #     tee "$HOME/Desktop/input-post.txt" | \
        doActualSsh "$@" | \
        sed $LINEBUFSEDSWITCH -e "$oxp" &
        local resumePid=$!
        while true; do
            debug_echo "Pre wait in loop..."
            DO_CONTINUE=false
            wait $resumePid
            errorStatus=$?
            debug_echo "Post wait in loop..."
            if [[ ${DO_CONTINUE} == true ]]; then
                debug_echo "Continuing loop..."
                continue
            fi
            break
        done
    fi
    if [[ "$RAISED_SIGNAL" == "SIGTERM" ]]; then
        debug_echo "SIGTERM was raised removing our handler..."
        trap - SIGTERM
        trap - INT
    fi
    if [[ -e "$ACTUAL_SSH_STATUS_FILE" ]]; then
        errorStatus="$(< "$ACTUAL_SSH_STATUS_FILE")"
        rm -f "$ACTUAL_SSH_STATUS_FILE"
    elif [[ -n "$ACTUAL_SSH_STATUS" ]]; then
        errorStatus="$ACTUAL_SSH_STATUS"
    fi 
    debug_echo "Post wait in loop ssh status is $errorStatus."
    debug_echo "$FUNCNAME: errorStatus is $errorStatus"
    return $errorStatus
}

hasSignalWrapper()
{
    [[ -n "$SIGWRAP_SIGINT_FILE" ]]
}

watchSignalWrapper()
{
    debug_echo "Watching for SIGINT"
    while true; do
        if [[ -e "$SIGWRAP_SIGINT_FILE" ]]; then
            debug_echo "Caught SIGINT from wrapper parent"
            rm -f $SIGWRAP_SIGINT_FILE >& /dev/null
            kill -SIGINT ${MY_PID} >& /dev/null
        fi
        sleep 0.5
    done
}

doActualSsh()
{
    if hasSignalWrapper; then
        watchSignalWrapper &
        local signalWrapperPid=$?
    fi
    ssh "$@"
    local errorStatus=$?
    debug_echo "$FUNCNAME: ACTUAL_SSH_STATUS is $errorStatus"
    # Write actual error status to a file to survive the
    # upcoming suicide of this thread.
    echo "$errorStatus" > "$ACTUAL_SSH_STATUS_FILE"

    if hasSignalWrapper; then
        kill -SIGTERM $signalWrapperPid
    fi
    # Only post mortem debugging needs the ssh stream to
    # "commit suicide" to properly close

    # We need to kill the debugging process to kill the pipes
    # which don't clean themselves up properly for
    # GDB DSF debugging
    if [[ $GDB_DSF_USE_TTY == false ]]; then
        kill -TERM $MY_PID
        wait $MY_PID 2> /dev/null
    fi
    return $errorStatus
}

remote_gdb_main_bash()
{
    # Make sure all variables have legacy escaping removed.
    verify_no_legacy_escaped_path_variables

    if [[ "$1" == "-pm" ]]; then
        export DSF_POST_MORTEM=true
        export DSF_ATTACH=false
        shift
    elif [[ "$1" == "-attach" ]]; then
        export DSF_POST_MORTEM=false
        export DSF_ATTACH=true
        shift
    else
        export DSF_POST_MORTEM=false
        export DSF_ATTACH=false
    fi

    if [[ "$1" == "-launchFile" ]]; then
        # Eclipse butchers handling of spaces and slashes and treating them
        # as separate arguments or munging them, so I must unescape them:
        # ' ' (space) => '[_]'
        # ':' => '/'
        # This escaping was done in instantiate-launch-template.sh
        local launchFile="${2//\[_\]/ }"
        launchFile="${launchFile//://}"
        shift 2
        debug_echo "launchFile is $launchFile"
        local fullLaunchFile="${PROJECT_PATH}/$launchFile"
        local fullLaunchPath="$(dirname "$fullLaunchFile")"
        debug_echo "fullLaunchPath is $fullLaunchPath"
        source "$fullLaunchPath/launchenv.sh"
    else
        # Must set certain things here if an old project has
        # no definiton of MAINBINARY, etc.
        :
    fi

    debug_echo "---------[START]---"
    debug_echo "PROJECT_NAME is $PROJECT_NAME"
    remote_gdb_common_get_binary
    translateGdbOptions "$@"
    debug_echo "OPTIONS are $OPTIONS"
    export MY_PID=$$
    OUTPUT_TTY_FILE="$SUBPROJECT/$MAINBINPATH/.outputTtyFile-pid$MY_PID"
    export REMOTE_PID_FILE="$SUBPROJECT/$MAINBINPATH/.remotePid-pid$MY_PID"
    export LOOP_PID_FILE="$SUBPROJECT/$MAINBINPATH/.loopPid-pid$MY_PID"
    export ACTUAL_SSH_STATUS_FILE="$SUBPROJECT/$MAINBINPATH/.actualSshStatus-pid$MY_PID"

    # sniemczyk: 2013-7-26: In Eclipse Kepler, the timeout for gdb --version
    # is really short, and for slower connections there is not enough time
    # to get its results.  So, we now cache the GDB version during the build
    # time, and then store the command that we would have called prior to
    # Kepler.  We now do that in the actual run pass, but early.
    if  [[ "$OPTIONS" != "--version" ]] && \
        [[ -e "$SUBPROJECT/$MAINBINPATH/tmpgdbveroutsc" ]]; then
        sc="$(< "$SUBPROJECT/$MAINBINPATH/tmpgdbveroutsc")"
        doGdbVersionPass
        sc=
        rm "$SUBPROJECT/$MAINBINPATH/tmpgdbveroutsc"
    fi

    if  [[ "$OPTIONS" != "--version" ]]; then
        if [[ -e "$SUBPROJECT/$MAINBINPATH/tmpgdbverout" ]]; then
            # Extract the major and minor version, i.e 6.1.1 => 61, 7.4 => 74
            local GDB_VER_LINE="$(grep "GNU gdb" \
                "$SUBPROJECT/$MAINBINPATH/tmpgdbverout")"
            local GDB_CFG_LINE="$(grep "was configured" \
                "$SUBPROJECT/$MAINBINPATH/tmpgdbverout" | \
                sed "s#\\(.*\\)\"\\(.*\\)\"\\(.*\\)#\\2#" )"
            RGDB_VERSION="$( echo "$GDB_VER_LINE" | \
                sed "s/GNU gdb.*[ \\(]\\([0-9]*\\)\.\\([0-9]*\\).*/\\1\\2/")"
            rm "$SUBPROJECT/$MAINBINPATH/tmpgdbverout"
            debug_echo GDB_VER_LINE is $GDB_VER_LINE.
            debug_echo GDB_CFG_LINE is $GDB_CFG_LINE.
            # For old GDB versions, the format of the command to update a
            # variable is different.  This provides backwards compatability
            # for GDB < 6.3.x
            if [[ "$GDB_CFG_LINE" != "${GDB_CFG_LINE/freebsd/}" ]]; then
                RGDB_OS=FreeBSD
            elif [[ "$GDB_CFG_LINE" != "${GDB_CFG_LINE/linux/}" ]]; then
                RGDB_OS=Linux
            else
                RGDB_OS=Unknown
            fi
        else
            RGDB_VERSION=0
            RGDB_OS=Unknown
        fi
        debug_echo "Detected GDB version $RGDB_VERSION on $RGDB_OS"
    fi
    
    # If we are debugging an actual launch (not attach or debug), get any variables set in the project
    # and use those variables to override the variables set elsewhere.  This way launches can now have
    # their own environment variables and they will be set locally customizing the behavior of a remote
    # launch. 
    if     [[ "$OPTIONS" != "--version" ]] && \
           [[ $DSF_POST_MORTEM == false ]] && [[ $DSF_ATTACH == false ]] && \
           [[ -e "$fullLaunchFile" ]]; then
        # Force EXECSW to be retrieved from the file, since Eclipse's cache is
        # stale for GDB (returns older values than the dialog box)
        project_export --force EXECSW

        get_launch_file_environment_variables "$fullLaunchFile"
    fi
    
    # Get EXECSW BINALIAS and other settings for running
    remote_gdb_common_get_exec_settings

    # Since we're already in the main project directory go back one
    local execfile="$bintorun"

    export ix # Input Sed eXpression
    ix="s#source $SUBPROJECT/$MAINBINPATH#source $MAINBINPATH#"
    if [[ "$DSF_POST_MORTEM" == "true" ]]; then
        ix="$ix;s#$MAINBINPATH/gdbinitpm#$MAINBINPATH/gdbinitpmdsf#"
        local gdbinitpmfile="$SUBPROJECT/$MAINBINPATH/gdbinitpm"
        local remotecore
        if [[ -e "$gdbinitpmfile" ]]; then
            #Shorten the name to keep the following lines short
            local gf="$gdbinitpmfile"
            remotecore="$(grep "^core" "$gf" | sed "s/^core //")"
            execfile="$(grep "^exec-file" "$gf" | sed "s/^exec-file //")"
        else
            remotecore=core_not_specified
        fi
        local corepre="target[-]select "
        local corecmd=core
        ix="$ix;s#\\([0-9][0-9]*[-]$corepre\\)core \\(.*\\)#\\1$corecmd $remotecore#"
    fi

    # Be sure to add the environment-cd patch here, because below we
    # may add another command which uses environemnt-cd as the post-pattern
    # for a change, thus if we do it after then we'll end up changing it twice.
    ix="$ix;s#\\([0-9][0-9]*[-]environment[-]cd \\)\\(.*\\)#\\1$EXECWD#"
    ix="$ix;s/\\([0-9][0-9]*[-]environment[-]directory \\)\\(.*\\)/\\1/"
    # Disable the logic to turn off shared-library events
    #ix="$ix;s/\\([0-9][0-9]*[-]gdb[-]set stop[-]on[-]solib[-]events\\) 1/\\1 0/"
    
    # Treat setting of variables EXECSW and EXECWD to a null value as being not set
    ix="$ix;s/\\([0-9][0-9]*[-]gdb[-]set env \\)\\(EXECSW\\).*/\\1__\\2 = X/"
    ix="$ix;s/\\([0-9][0-9]*[-]gdb[-]set env \\)\\(EXECWD\\).*/\\1__\\2 = X/"

    local execsympre1
    execsympre1="file[-]exec[-]and[-]symbols [-][-]thread[-]group i1 "
    execsympre2="file[-]exec[-]and[-]symbols "
    ix="$ix;s#\\([0-9][0-9]*[-]$execsympre1\\)\\(.*\\)#\\1 \"$execfile\"#"
    ix="$ix;s#\\([0-9][0-9]*[-]$execsympre2\\)\\(.*\\)#\\1 \"$execfile\"#"

    # For platforms that try to set a tty, do not set up one: we do this
    # by replacing it with a no-op, that is, doing a "cd ."
    local ttypre="inferior[-]tty[-]set "
    local ttypost="environment-cd ."
    ix="$ix;s#\\([0-9][0-9]*[-]\\)\\($ttypre\\)\\(.*\\)#\\1$ttypost#"
    # For old versions of GDB, we need to change the command we give for
    # updating variables.
    if [[ $RGDB_VERSION -lt 63 ]]; then
        ix="$ix;s#\\([0-9][0-9]*[-]var[-]update \\)[0-9] \\(.*\\)#\\1\\2#"
    fi

    # The argument field in eclipse contains the relative path to the bash
    # script we run to launch outside of the debugger.  When actually in the
    # debugger, we need to put the arguments value we have, the $EXECSW.
    # Note since this value is being evaluated in a sed replacement, we need
    # to properly escape it. Also Note the outer double quotes around EXECSW,
    # which makes gdb interpret the spaces between arguments within quotes as
    # part of the same argument.
    local varvalue="${EXECSW}"
    # We need to wrap the switches in two double-quotes ("") to properly
    # treat quotes within as separating values.  That said, if the string
    # is completely blank, that means no arguments at all (and thus, no quotes)
    if [[ -n "${varvalue}" ]]; then
        varvalue="${varvalue//\\/\\\\\\\\}"
        varvalue="${varvalue//\#/\\#}"
        varvalue="${varvalue//\&/\\&}"
        varvalue=" \\\"\\\"${varvalue}\\\"\\\""
    fi
    # Let's define a pattern for an optional single or double quote (and optional space)
    local optQ="[\"']\\{0,1\\}"

    # Let's look for all arguments up to the -rt "${workspace_loc:remote_eclipse}"
    # Eclipse test runners will insert arguments after the normal list of arguments
    # we place in the launch file.  This way those extra arguments make it to the
    # end of the argument list, and existing EXECSW come first
    local argPattern="${optQ}$MAINBINPATH/[-_a-z]*\\.sh${optQ} .* ${optQ}-rt${optQ} .*[\\\\/]remote_eclipse${optQ}"
    # Note no leading space before ${varvalue}, we get add it only
    # if varvalue is not blank (done above).
    ix="$ix;s#args ${argPattern}#args${varvalue}#"
    ix="$ix;s#arguments ${argPattern}#arguments${varvalue}#"

    local rbinpath="$REMOTEPROJECTDIR/$SUBPROJECT/$MAINBINPATH"
    local sc #SSH Command

    # Embed the local PID is the command so it is visible by process_grep, when
    # the time comes to search for the remote ssh call for this gdb session.
    sc="LOCAL_MY_PID=$$"
    sc="$sc; cd $RWSDIR/$PROJECT_NAME"
    # If we are attaching, there's no switches or library paths to set.
    if [[ $DSF_ATTACH == false ]] && [[ $DSF_POST_MORTEM == false ]]; then
        # Escape any variables that have quotes so that one can pass arguments
        # with spaces in them.
        sc="$sc; if [[ -e $rbinpath/ldlibrarypath ]]; then"
        sc="$sc    export LD_LIBRARY_PATH=\$(cat $rbinpath/ldlibrarypath)"
        sc="$sc; fi"
        sc="$sc; if [[ -e $rbinpath/env.sh ]]; then"
        sc="$sc    source $rbinpath/env.sh"
        sc="$sc; fi"
    fi

    if  [[ "$OPTIONS" == "--version"    ]] && \
        [[ $DSF_POST_MORTEM == true ]]; then
        local sedexp="\"/^exec-file/d;/^symbol-file/d;/^core/d\""

        sc="$sc; sed $sedexp ${gdbinitpmfile} > ${gdbinitpmfile}dsf"
        sc="$sc; sed \"s/\\(.*\\)/~~\\1/\" $gdbinitpmfile"
    fi

    local gdbcommand
    get_remote_gdb_bin gdbcommand

    sc="$sc; $gdbcommand $OPTIONS"

    export oxp
    export ox1
    export ox2
    export ox3
    export ox4

    # oxp is for path translation (as passed with template)
    oxp="${DEBUGGER_PATH_SEDEXP}"

    local msg1="No symbol \\\\\"new\\\\\" in current context."
    ox1="s/\\([0-9][0-9]*\\)^error,msg=\"$msg1\"/\\1^done/;/&\"$msg1\\\\n\"/d"
    if [[ $DSF_ATTACH == true ]] && [[ $RGDB_OS == FreeBSD ]]; then
        local pattern="/$MAINBINARY"
        # If the binary is run via an alias, search for
        # executions via the alias's name too
        if [[ "$BINALIAS" != "$MAINBINARY" ]]; then
            pattern="$pattern|/$BINALIAS|\\($MAINBINARY\\)"
        fi
        local pidList="$(getFreeBSDPidList "$remoteuser" "$remotehost" "$pattern")"
        local msg2in="msg=\"Can not fetch data now.\""
        local msg2out="groups=[${pidList}]"
        ox1="$ox1;s#\\([0-9][0-9]*\\)^error,$msg2in#\\1^done,${msg2out}#"
    fi
    ox2="s/.*/#~~#&/"
    ox3="s/#~~#\\((gdb)\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9][0-9]*^done\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9][0-9]*^running\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9][0-9]*^exit\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9][0-9]*^error\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9]*\*stopped,\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9]*\*running,\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9]*=thread[-]\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9]*=breakpoint[-]\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([0-9]*=library[-]\\)\\(.*\\)/\\1\\2/"
    ox3="$ox3;s/#~~#\\([~@&]\\)\\(\"\\)\\(.*\\)/\\1\\2\3/"
    ox4="s/#~~#\\(.*\\)/@\"\\1\\\\n\"/"
    # Escape the output lines: @"output text\n" to escape any backslashes
    # and double quotes.  The first line here says what follows only applies
    # to output lines.  The rest converts backslashes to double backslates and
    # quotes to backslash quotes.  It also undoes this to the beginning and end
    # of the line, which should not have their quotes and backslashes escaped.
    if [[ $GDB_DSF_USE_TTY == false ]]; then
        ox4="$ox4;/^@\"\\(.*\\)\\\\n\"\$/ {"
        ox4="$ox4 s/\\\\/\\\\\\\\/g;s/\"/\\\\\"/g"
        ox4="$ox4;s/\\\\\\\\n\\\\\"\$/\\\\n\"/;s/^@\\\\\"/@\"/"
        ox4="$ox4; }"
    fi

    if  [[ "$OPTIONS" == "--version" ]]; then
        if [[ -e "$SUBPROJECT/$MAINBINPATH/tmpgdbveroutsc" ]]; then
            rm "$SUBPROJECT/$MAINBINPATH/tmpgdbveroutsc"
        fi
        if [[ -e "$SUBPROJECT/$MAINBINPATH/gdbverout" ]]; then
            echo "$sc" > "$SUBPROJECT/$MAINBINPATH/tmpgdbveroutsc"
            cat "$SUBPROJECT/$MAINBINPATH/gdbverout"
            debug_echo "$(date): Wrote gdb version from cached gdbverout"
        else
            doGdbVersionPass
            # Write out the gdb version (the lines that don't start with ~~)
            cat "$SUBPROJECT/$MAINBINPATH/tmpgdbverout" | grep -v "^~~"
            debug_echo "$(date):Wrote gdb version from ssh interrogation"
        fi
    elif [[ "$DSF_POST_MORTEM" == "true" ]]; then
        sc="$sc; rm -f ${gdbinitpmfile}dsf"
        # DSF post-mortem debugging does not work with output wrappers
        unset ox1
        doGdbSsh -C "$remoteuser@$remotehost" "bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$sc'"
    else
        doGdbSsh -C "$remoteuser@$remotehost" "bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$sc'"
    fi
    errorStatus=$?

    debug_echo "$FUNCNAME: errorStatus is $errorStatus"
    debug_echo "---------[DONE]----"
    # Done
    return $errorStatus
}

remote_gdb_main_bash "$@"
