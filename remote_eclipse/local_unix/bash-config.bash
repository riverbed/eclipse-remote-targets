#! /bin/bash
#
# bash-config.bash -- common setup for all Unix bash launch points
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

function pause()
{
    read -p "Press enter to continue . . . "
}
export -f pause

function makeBashLink()
{
    local binbash=/bin/bash
    local makelink=true
    if [[ -e "$1" ]]; then
        local targetmd5="$(get_md5 "$1")"
        local bashmd5="$(get_md5 "$binbash")"
        if [[ "$bashmd5" == "$targetmd5" ]]; then
            makelink=false
        else
            # If a binary or link was already there, delete it.
            rm -f "$1"
        fi 
    fi
    if [[ "$makelink" == "true" ]]; then
        ln -s $binbash "$1"
    fi
}
export -f makeBashLink

function local_error_filter()
{
    # If we have errors due to this bash environment itself, let's have these
    # errors show in Eclipse
    local SEDEXP
    SEDEXP="$SEDEXP;s#\(\.sh:\) line \([0-9][0-9]*:\)#\1\2#"
    SEDEXP="${SEDEXP:1}"
    { "$@" 2>&1 >&3 | \
    sed $LINEBUFSEDSWITCH "$SEDEXP" >&2; } 3>&1
    return ${PIPESTATUS[0]}
}
export -f local_error_filter

launch_xterm_do()
{
    export PATH="$LAUNCH_XTERM_PATH"
    eval "$LAUNCH_XTERM_DO"
}
export -f launch_xterm_do

launch_xterm()
{
    local title=xterm
    if [[ "$1" == "-title" ]]; then
        title="$2"
        shift 2
    fi
    export LAUNCH_XTERM_PATH="$PATH"
    export LAUNCH_XTERM_DO="$@"
    
    $PLATFORM_XTERM_BIN -T "$title" -e bash -c launch_xterm_do
    local _status=$?
    eval $PLATFORM_XTERM_POST_RUN_ACTION
    return ${_status}
}
export -f launch_xterm

if [[ -z "$TMPDIR" ]]; then
    export TMPDIR=/tmp
fi

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

if [[ -n "$PROJECT_LOC" ]]; then
    export PROJECT_PATH="$PROJECT_LOC"
fi
export WORKSPACE_PATH="$WORKSPACE_LOC"
export REMOTE_ECLIPSE_PATH="$REMOTE_ECLIPSE_LOC"
export PLATFORM_BREAK_KEY="Ctrl+C"

# If a Unix platorm defines a binary directory to supersede the generic
# unix ones, prepend the path with it.
if [[ -n "$PLAT_BIN_DIR" ]]; then
    export PATH="$PLAT_BIN_DIR:$PATH"
    source bash-config-platform.bash
fi

# Find git, in case it isn't already in the path.
if [[ -z "$(which git >& /dev/null)" ]]; then
    if [[ -e /usr/local/bin/git ]]; then
        export PATH=$PATH:/usr/local/bin
    elif [[ -e /usr/local/git/bin/git ]]; then
        export PATH=$PATH:/usr/local/git/bin
    fi
fi
