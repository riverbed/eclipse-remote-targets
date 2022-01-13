#! /bin/bash
#
# rbinlaunch.sh -- Launcher to wrap platform-specific launcher for Run action
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# Are you not running Windows (msys or win32)?  Thus we need an exit handler
if [[ "$OSTYPE" == "${OSTYPE/msys/}" ]] && [[ "$OSTYPE" == "${OSTYPE/win32/}" ]]; then
    export REMOTE_ACTION_PPID=$$
    trap on_exit EXIT
    on_exit()
    {
        if [[ "$OSTYPE" != "${OSTYPE/linux/}" ]]; then
            # For linux, omit the dash
            local ax_switch=ax
        else
            # For OS X and FreeBSD, use a dash
            local ax_switch=-ax
        fi
        local child_pids=$(ps -o pid,command $ax_switch | grep -v grep | \
        grep " REMOTE_ACTION_PPID=$REMOTE_ACTION_PPID;" | \
        awk '{ print $1 }' | xargs)

        if [[ -n "$child_pids" ]]; then
            kill -TERM $child_pids >& /dev/null
        fi
    }
fi

exit_with_error()
{
    set_stack_frame_location
    echo "$@" 1>&2
    exit 1
}

doExecRemoteAction()
{
    local launchDir="$(dirname "${BASH_SOURCE[0]}")"
    local launchEnvScript="$launchDir/launchenv.sh"
    if [[ ! -e "$launchEnvScript" ]]; then
        exit_with_error "No launch environment script found. Cannot execute."
    fi

    # Grab enviornment variables from the script
    source "$launchDir/launchenv.sh"

    if [[ -z "$LOCALPROJECTNAME" ]]; then
        exit_with_error "No local project name found in" \
            "launch environment script."
    fi
    export PROJECT_NAME="$LOCALPROJECTNAME"

    if [[ $1 != "-os" ]]; then
        exit_with_error "No system OS detected. Cannot execute."
    fi

    ECLIPSE_SYSTEM_OS=$2
    shift 2

    if [[ $1 != "-wl" ]]; then
        exit_with_error "No workspace location given. Cannot execute."
    fi

    export WORKSPACE_LOC="$2"
    shift 2

    if [[ $1 != "-pl" ]]; then
        exit_with_error "No project location given. Cannot execute."
    fi

    export PROJECT_LOC="$2"
    shift 2

    if [[ $1 != "-rt" ]]; then
        exit_with_error "No remote_eclipse location given. Cannot execute."
    fi

    export REMOTE_ECLIPSE_LOC="$2"
    shift 2

    local RESOURCE_PATH="/$PROJECT_NAME"
    cd "$REMOTE_ECLIPSE_LOC"
    REMOTE_ECLIPSE_PATH="$PWD"
    cd "$WORKSPACE_LOC"
    WORKSPACE_PATH="$PWD"
    cd "$PROJECT_LOC"
    PROJECT_PATH="$PWD"
    local SYS_OS_PATH="$REMOTE_ECLIPSE_PATH/local_os/$ECLIPSE_SYSTEM_OS"
    "$SYS_OS_PATH/remote-action.bash" -exec "$RESOURCE_PATH" exec "$@"
}
doExecRemoteAction "$@"
