#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source common-remote-functions.sh

watcher_echo()
{
    : # Uncomment the line below to watch the watcher
    # echo "$@" >> /tmp/watcher-log.txt
}

exec_watcher()
{
    trap 'true' SIGUSR1

    local pppid=$1
    local ppid=$2
    local bintorun=$3
    local watchedpid=unknown
    local watchedppid=$pppid
    local i=0

    local firstSignal=INT
    local signal=$firstSignal

    while [[ -n "$watchedpid" ]]; do
        sleep 5 &
        wait
        let i=$i+1
        # Only look for processes launched by this parent script
        watchedpid=$(pgrep -P $ppid -f "$bintorun")
        if [[ -z "$watchedpid" ]]; then
            break
        fi
        watcher_echo "i=$i, PPID=$ppid, for PID=$watchedpid."
        # Has the sshd process stopped running?
        if ! kill -0 $pppid >/dev/null 2>&1; then
            # If so, we should stop the watched process
            watcher_echo "Shell has stopped."
            pkill -${signal} -P $watchedpid >/dev/null 2>&1
            kill -${signal} $watchedpid >/dev/null 2>&1
            if [[ "$signal" == "$firstSignal" ]]; then
                # If the next time around it is still running, try TERM
                signal=TERM
            else
                # Then finally try kill.
                signal=KILL
            fi
        fi
    done
    watcher_echo "Watcher exiting."
}

exec_generic_main()
{
    export SUBPROJECTDIR=$REMOTEPROJECTDIR/$SUBPROJECT
    # If the SUBPROJECTDIR ends in /. strip it off
    SUBPROJECTDIR=${SUBPROJECTDIR%/.}

    if [[ -z "$BINALIAS" ]]; then
        BINALIAS=$MAINBINARY
    fi
    
    local bintorun=$MAINBINLTSUBDIR/$BINALIAS
    case bintorun in
        ./*/*)
            # Only strip off the ./ if there is at least one slash in the path
            # otherwise, it won't run the program in the current directory since
            # "." is not likely in the path
            bintorun=${bintorun#./}
            ;;
    esac

    if [[ ! -e $SUBPROJECTDIR ]]; then
        wait_then_exit_with_error "$SUBPROJECT not checked out. Cannot execute binary."
    fi

    cd $SUBPROJECTDIR

    if [[ ! -e $MAINBINSUBDIR/$lt_MAINBINARY || \
          ! -e $MAINBINLTSUBDIR/$MAINBINARY  || \
          ! -e $bintorun                     ]]; then
        wait_then_exit_with_error "Binaries not found.  Build $SUBPROJECT first."
    fi

    if [[ -e $bintorun.gmon ]]; then
        echo rm $bintorun.gmon
        rm $bintorun.gmon
    fi

    # If there is no working directory specified, run from the sub-project directory.
    if [[ -z "$EXECWD" ]] || [[ "$EXECWD" == "." ]]; then
        EXECWD="$SUBPROJECTDIR"
        local spdirsl=""
    else
        # We are running in a supplied working directory, so let's use
        # explicit full paths to known files below
        local spdirsl="$SUBPROJECTDIR/"
        # If we always prepend the binary with the full SUBPROJECTDIR,
        # we can strip the leading ./ because we will have a full path
        bintorun=${bintorun#./}
    fi

    local cmd1="cd $EXECWD"
    local cmd2=""
    if [[ -e $SUBPROJECTDIR/$MAINBINPATH/env.sh ]]; then
        cmd2="source ${spdirsl}$MAINBINPATH/env.sh"
    fi
    # Launch a watcher to terminate the executable if the ssh session terminates
    exec_watcher $PPID $$ "$bintorun" &
    local watcherpid=$!
    local escapedEXECSW="${EXECSW//\\/\\\\}"
    if [[ -z "$PIPETO" ]]; then
        if [[ "$SHOW_EXEC_PARAMS" == "true" ]]; then
            if [[ "$cmd2" == "" ]]; then
                echo "$cmd1; ${spdirsl}$bintorun $EXECSW"
            else
                echo "$cmd1; $cmd2; ${spdirsl}$bintorun $EXECSW"
            fi
        fi
        if [[ "$cmd2" == "" ]]; then
            $cmd1; eval ${spdirsl}$bintorun $escapedEXECSW
        else
            $cmd1; $cmd2; eval ${spdirsl}$bintorun $escapedEXECSW
        fi
        errorStatus="$?"
    else
        if [[ "$SHOW_EXEC_PARAMS" == "true" ]]; then
            if [[ "$cmd2" == "" ]]; then
                echo "$cmd1; ${spdirsl}$bintorun $EXECSW | $PIPETO"
            else
                echo "$cmd1; $cmd2; ${spdirsl}$bintorun $EXECSW | $PIPETO"
            fi
        fi
        if [[ "$cmd2" == "" ]]; then
            $cmd1; eval ${spdirsl}$bintorun $escapedEXECSW | $PIPETO
        else
            $cmd1; $cmd2; eval ${spdirsl}$bintorun $escapedEXECSW | $PIPETO
        fi
        errorStatus="${PIPESTATUS[0]}"
    fi

    if [[ -e $BINALIAS.gmon ]]; then
        echo "gprof ${spdirsl}$MAINBINSUBDIR/$lt_MAINBINARY $BINALIAS.gmon \| c++filt"
        gprof ${spdirsl}$MAINBINSUBDIR/$lt_MAINBINARY $BINALIAS.gmon | c++filt
    fi

    # Interrupt the watcher, if it is still running
    local sleepPid=$(pgrep -P $watcherpid)
    if [[ -n "$sleepPid" ]]; then
        kill -SIGUSR1 $sleepPid
    fi

    debug_echo "$FUNCNAME: errorStatus is $errorStatus"
    return $errorStatus
}

exec_generic_main "$@"
