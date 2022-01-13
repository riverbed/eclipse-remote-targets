#! /bin/bash
#
# build.bash -- wrapper to launch windows build.bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

export ECLIPSE_SYSTEM_OS="$(basename "$(dirname "${BASH_SOURCE[0]//\\//}")")"

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
    export REMOTE_ECLIPSE_LOC="${BASH_SOURCE[0]%\\local_os\\*}"
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
    local OPTIONS=
    until [[ -z "$1" ]]; do
        local value="$1"
        shift
        
        # Due to msys's bash expansion of ~~ to /, we undo that expansion
        if [[ "${value}" == "/" ]]; then
            # msysgit requires ~~ to be quoted.
            value="~~"
        fi
        # Also make sure any backslash paths are forward slashes
        OPTIONS="$OPTIONS '${value//\\//}'"
    done
    local OPTIONS="${OPTIONS:1}"

    eval "'$REMOTE_ECLIPSE_LOC/local_windows/build.bash' $OPTIONS"
}

build_target_main "$@"
