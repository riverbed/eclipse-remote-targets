#! /bin/bash
#
# build.bash -- wrapper to launch all-unix build.bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export ECLIPSE_SYSTEM_OS="$(basename "$(dirname "${BASH_SOURCE[0]}")")"
export PLAT_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/bin && pwd)"

export REMOTE_ACTION_PPID=$$
trap on_exit EXIT
on_exit()
{
    # On Linux use ps ax without dash
    local child_pids=$(ps -o pid,command ax | grep -v grep | \
        grep " REMOTE_ACTION_PPID=$REMOTE_ACTION_PPID;" | \
        awk '{ print $1 }' | xargs)

    if [[ -n "$child_pids" ]]; then
        kill -TERM $child_pids >& /dev/null
    fi
}

build_target_main()
{
    if [[ "$1" == "-env" ]]; then
        # All projects that have the environment provided at setup
        # must be at least version 0.9 —  that is the widely used
        # once in git but before official versioning in 2018.
        export ECLIPSE_RT_VERSION_AT_SETUP=0.9
        shift
        build_target_without_env_vars_main "$@"
    else
        # These are ancient projects made before the move to git.
        export ECLIPSE_RT_VERSION_AT_SETUP=0.1
        build_target_with_env_vars_main "$@"
    fi
}

build_target_without_env_vars_main()
{
    export REMOTE_ECLIPSE_LOC="${BASH_SOURCE[0]%/local_os/*}"
    local seenWlParameter=false

    while [[ "$1" != "${1#-}" ]]; do
        case $1 in
            -wl)
                # Reuse -wl parameter to hide the version at setup since it
                # will be safely ignored by older versions of Eclipse for RT.
                # This is a backwards compatible way of starting to serialize
                # the version at setup inside Eclipse for RT projects.
                if [[ $seenWlParameter == true ]]; then
                    export ECLIPSE_RT_VERSION_AT_SETUP="${WORKSPACE_LOC}"
                fi
                seenWlParameter=true
                export WORKSPACE_LOC="$2"
                shift 2
                ;;
            -pl)
                export PROJECT_LOC="$2"
                shift 2
                ;;
            -pn)
                export PROJECT_NAME="$2"
                shift 2
                ;;
            -cn)
                export CONFIGNAME="$2"
                shift 2
                ;;
             -sv)
                # Not currently written by the setup process, but in the
                # future we will use this parameter to write the version
                # at setup.
                export ECLIPSE_RT_VERSION_AT_SETUP="$2"
                shift 2
                ;;
             *)
                break
                ;;
        esac
    done
    build_target_with_env_vars_main "$@"
    return
}

build_target_with_env_vars_main()
{
    "$REMOTE_ECLIPSE_LOC/local_unix/build.bash" "$@"
}

build_target_main "$@"
