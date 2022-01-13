#! /bin/bash
#
# bash-config.bash -- common setup for all Windows bash launch points
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# For ssh function below
source local-remote-common-aliases.sh

function pause()
{
    read -p "Press enter to continue . . . "
}
export -f pause

function get_md5()
{
    md5sum "$@" | sed 's/\([0-9a-f]*\) .*/\1/'
}
export -f get_md5

process_grep()
{
    # Note, this process_grep will not work for arguments. Luckily,
    # we don't need process_grep for gdb on Windows: it is only needed
    # when we emulate tty.
    ps -s | grep -v grep | \
        grep -e "$1" | awk '{ print $1 }' | xargs
}
export -f process_grep

function makeBashLink()
{
    local binbash="$(which bash.exe)"
    local makelink=true
    if [[ -e "$1" ]]; then
        local targetmd5="$(get_md5 "$1")"
        local bashmd5="$(get_md5 "$binbash")"
        if [[ "$bashmd5" == "$targetmd5" ]]; then
            makelink=false
        fi 
    fi
    if [[ "$makelink" == "true" ]]; then
        cp "$binbash" "$1"
    fi
}
export -f makeBashLink

function local_error_filter()
{
    # If we have errors due to this bash environment itself, let's have these
    # errors show in Eclipse
    local SEDEXP
    SEDEXP="$SEDEXP;s#\(\.sh:\) line \([0-9][0-9]*:\)#\1\2#"
    SEDEXP="$SEDEXP;s#${PROJECT_PATH}#${PROJECT_LOC//\\/\/}#"
    SEDEXP="$SEDEXP;s#${REMOTE_ECLIPSE_PATH}#${REMOTE_ECLIPSE_LOC//\\/\/}#"
    SEDEXP="${SEDEXP:1}"
    { "$@" 2>&1 >&3 | \
    sed $LINEBUFSEDSWITCH "$SEDEXP" >&2; } 3>&1
    return ${PIPESTATUS[0]}
}
export -f local_error_filter

function get_rsync_for_windows()
{
    local msysRsyncVersion=msys_version_not_detected
    local unameType="$(uname)"
    if [[ "${unameType}" != "${unameType#MINGW32}" ]]; then
        msysRsyncVersion=msys_1.0.19_rsync_3.0.8
    elif [[ "${unameType}" != "${unameType#MSYS_NT}" ]]; then
        if [[ "${unameType}" != "${unameType%-WOW}" ]]; then
            msysRsyncVersion=msys_2_i686_rsync_3.1.3-1
        else
            msysRsyncVersion=msys_2_x86_64_rsync_3.1.3-1
        fi  
    fi
    local puttyver=0.70
    local ext_bins="${REMOTE_ECLIPSE_LOC%\\remote_eclipse}\\external_binaries"
    
    export MSYSRSYNCPATH="${ext_bins}\\$msysRsyncVersion"
    if    [[ ! -e "$MSYSRSYNCPATH\\bin\\rsync.exe"    ]] || \
          [[ ! -e "$MSYSRSYNCPATH\\bin\\puttygen.exe" ]]; then
        echo
        echo Installing ${msysRsyncVersion} ...
        echo
        local msysRsynczip=${msysRsyncVersion}.zip
        local msysRsyncurl=http://releng.nbttech.com/npm/mirrors/msys_rsync/${msysRsynczip}
        local pzip=putty.zip
        local pzurl="http://the.earth.li/~sgtatham/putty/$puttyver/w32/${pzip}"
        
        pushd "$ext_bins" >& /dev/null && \
        touch msys_rsync_dummy.txt && \
        rm -rf *Rsync_* *rsync_* tmp && \
        mkdir -p ./${msysRsyncVersion}/bin && \
        mkdir -p ./${msysRsyncVersion}/lib && \
        cd ./${msysRsyncVersion} && \
        touch dummy.dll && \
        curl ${msysRsyncurl} -o ${msysRsynczip} && \
        unzip ${msysRsynczip} && \
        mv *.dll lib/. && \
        rm lib/dummy.dll && \
        mv *.exe bin/. && \
        rm ${msysRsynczip} && \
        cd .. && \
        mkdir -p ./tmp && \
        curl ${pzurl} -o ./tmp/${pzip} && \
        pushd ./tmp >& /dev/null && \
        unzip ./${pzip} && \
        popd >& /dev/null && \
        mv ./tmp/puttygen.exe ./${msysRsyncVersion}/bin/. && \
        rm -rf ./tmp && \
        popd >& /dev/null
        
        if    [[ ! -e "$MSYSRSYNCPATH\\bin\rsync.exe"    ]] || \
              [[ ! -e "$MSYSRSYNCPATH\\bin\puttygen.exe" ]]; then
            exit_with_error "Failed install of rsync.exe and puttygen.exe."
        fi
    fi
}
export -f get_rsync_for_windows

function get_sigwrap_for_msys2()
{
    local unameType="$(uname)"
    if [[ "${unameType}" != "${unameType#MINGW32}" ]]; then
        # No wrapper needed for MSYS 1
        return
    fi

    local sigwrapVersion=unknown
    if [[ "${unameType}" != "${unameType#MSYS_NT}" ]]; then
        if [[ "${unameType}" != "${unameType%-WOW}" ]]; then
            sigwrapVersion=sigwrap_1.0_i686
        else
            sigwrapVersion=sigwrap_1.0_x86_64
        fi  
    else
        exit_with_error "Unknown version of msys"
    fi
    
    local ext_bins="${REMOTE_ECLIPSE_LOC%\\remote_eclipse}\\external_binaries"
    
    export SIGWRAPPATH="${ext_bins}\\$sigwrapVersion\\bin"
    export LOCAL_DEBUGGER_WRAPPER="\"${SIGWRAPPATH//\\/\/}/sigwrap\""
    if [[ ! -e "$SIGWRAPPATH\\sigwrap.exe" ]]; then
        echo
        echo Installing ${sigwrapVersion} ...
        echo
        local sigwrapZip=${sigwrapVersion}.zip
        local sigwrapUrl=http://releng.nbttech.com/npm/mirrors/sigwrap/${sigwrapZip}
        
        pushd "$ext_bins" >& /dev/null && \
        touch sigwrap_dummy.txt && \
        rm -rf *sigwrap* tmp && \
        mkdir -p ./${sigwrapVersion}/bin && \
        cd ./${sigwrapVersion} && \
        touch dummy.dll && \
        curl ${sigwrapUrl} -o ${sigwrapZip} && \
        unzip ${sigwrapZip} && \
        mv *.dll bin/. && \
        rm bin/dummy.dll && \
        mv *.exe bin/. && \
        mv library.zip bin/. && \
        mv *.pyd bin/. && \
        rm ${sigwrapZip} && \
        popd >& /dev/null
        
        if [[ ! -e "$SIGWRAPPATH\\sigwrap.exe" ]]; then
            exit_with_error "Failed install of sigwrap.exe."
        fi
    fi
}
export -f get_sigwrap_for_msys2

# Define ssh to use exec-watcher.sh only for msys2.
UNAME_TYPE="$(uname)"
if [[ "${UNAME_TYPE}" != "${UNAME_TYPE#MSYS_NT}" ]]; then
    get_sigwrap_for_msys2
    ssh()
    {
        trace_off
        # The explicit forwarding of stdin, stdout, etc. is necessary to
        # allow input when executing or preventing complains about pseudo terminal.
        /usr/bin/ssh "$@" < /dev/stdin > /dev/stdout 2> /dev/stderr &
        local mySshPid=$!
        exec-watcher.sh $mySshPid &
        disown
        wait $mySshPid
        trace_restore
    }
    export -f ssh
fi

launch_xterm()
{
    local title=xterm
    if [[ "$1" == "-title" ]]; then
        title="$2"
        shift 2
    fi
    
    # If we are about to run a bash shell inside a command prompt shell, there
    # is a need to force reimporting of all sourced headers.  This command
    # effectively does that.
    local command=$(set | grep '_SOURCED=true$' | \
        sed 's#\(.*\)=true#unset \1;#' | tr '\n' ' ')
    command="${command%; }"
    if [[ -n "$command" ]]; then
        eval "$command"
    fi
    
    # Because msys won't escape with quotes the title unless it has at least a
    # space in it, let's force one at the end in case the title doesn't have
    # one        
    if [[ "$title" == "${title/ /}" ]]; then
        title="$title "
    fi
    
    xterm-win-helper.bash "$title" "$@"
}
export -f launch_xterm

find()
{
    /bin/find "$@"
}
export -f find

sort()
{
    /bin/sort "$@"
}
export -f sort

export LINEBUFSEDSWITCH="-u"
export GDB_DSF_USE_TTY=false
if [[ -z "$TMPDIR" ]]; then
    export TMPDIR="$TEMP"
fi
export USER="$USERNAME"
export PLATFORM_BREAK_KEY="Ctrl+C"

cd .

# If we are in a remote debugging session and we have the variable
# ProjName, copy it to the all caps env variable we are looking
# for, the one used in the other modes (build or execution).
if [[ -n "$ProjName" ]]; then
    export PROJECT_NAME="$ProjName"
fi

# If we are in a remote debugging session and we have the variable
# ProjDirPath, copy it to the all caps env variable we are looking
# for, the one used in the other modes (build or execution).
if [[ -n "$ProjDirPath" ]]; then
    export PROJECT_LOC="$ProjDirPath"
fi

# NOTE BELOW: in Windows, this variable gets changed to caps for
# older versions of git bash because this shell was called from
# within a Windows command shell.

# If we are in a remote debugging session and we have the variable
# ProjName, copy it to the all caps env variable we are looking
# for, the one used in the other modes (build or execution).
if [[ -n "$PROJNAME" ]]; then
    export PROJECT_NAME="$PROJNAME"
fi

# If we are in a remote debugging session and we have the variable
# ProjDirPath, copy it to the all caps env variable we are looking
# for, the one used in the other modes (build or execution).
if [[ -n "$PROJDIRPATH" ]]; then
    export PROJECT_LOC="$PROJDIRPATH"
fi

if [[ -n "$PROJECT_LOC" ]]; then
    pushd "$PROJECT_LOC" > /dev/null
    export PROJECT_PATH="$PWD"
    popd > /dev/null
fi

pushd "$WORKSPACE_LOC" > /dev/null
export WORKSPACE_PATH="$PWD"
popd > /dev/null

pushd "$REMOTE_ECLIPSE_LOC" > /dev/null
export REMOTE_ECLIPSE_PATH="$PWD"
popd > /dev/null

pushd "$USERPROFILE" > /dev/null
export HOME="$PWD"
popd > /dev/null

ECLIPSE_HOME="$(dirname "$(which eclipse.exe 2>/dev/null)")"

# Make a fake gcc and g++ binary in Eclipse's home so the autodiscovery logic
# will find gcc and g++ in the PATH.  This is important on Windows where we
# use msysgit and thus there is no actual gcc and g++ installed on the box.
# Note that if it can't find it, ECLIPSE_HOME will be "."
if [[ -n "${ECLIPSE_HOME#.}" ]] && [[ ! -e "$ECLIPSE_HOME/gcc.exe" ]]; then
    makeBashLink "$ECLIPSE_HOME/gcc.exe"
    makeBashLink "$ECLIPSE_HOME/g++.exe"
fi
