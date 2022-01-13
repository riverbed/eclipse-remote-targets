#! /bin/bash
# do-action-internal.sh
#
# This script is called when attempting to build or execute a particular
# part of the workspace, after the environment variables have already been
# set (see do-action.sh)
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

#include common functions
source common-remote-functions.sh

do_action_internal_main()
{
    local project=$1
    shift

    local projectName="$LOCALPROJECTNAME/$project"
    projectName="${projectName%/.}"
    export SUBPROJECT=$project
    export PROJECT_PATH=$REMOTEPROJECTDIR
    export SUBPROJECTDIR=$REMOTEPROJECTDIR/$SUBPROJECT
    SUBPROJECTDIR=${SUBPROJECTDIR%/.}
    cd $SUBPROJECTDIR

    # This file is no longer used for remote detection, so we can remove it.
    if [ -e $REMOTEPROJECTDIR/.remoteexists ]; then
        rm -f $REMOTEPROJECTDIR/.remoteexists
    fi

    local action=
    local buildScript=

    local multiActionScript=
    find_multi_action_script multiActionScript $SUBPROJECT

    if [ -e "$multiActionScript" ]; then
        buildScript="$multiActionScript"
        action=-remote
    else
        #Set a list of alternate scripts, preferred ones first
        local buildScripts
        buildScripts="./doCustomAction.sh ./build-me"
        buildScripts="${buildScripts} do-action-$project.sh build-$project"

        local script
        for script in $buildScripts; do
            debug_echo "Trying script $script"
            local foundScript="$(which "$script" 2> /dev/null)"

            # If the script is found, this won't be blank
            if [ -n "$foundScript" ]; then
                debug_echo "Found script $script, breaking..."
                buildScript="$foundScript"
                break
            fi
        done
    fi

    if [ -z "$buildScript" ]; then
        wait_then_exit_with_error "Cannot find a build script for $projectName..."
    fi

    $buildScript $action "$@"
    local errorStatus="$?"
    if [[ "$errorStatus" != "0" ]]; then
        set_stack_frame_location -file $buildScript
        wait_then_exit_with_error "$projectName $buildActionLabel failed."
    elif [[ $dotest == true ]]; then
        # If we succeeded and we were doing a test, add an info so we can see it.
        set_stack_frame_location -file $buildScript
        show_info "$projectName $buildActionLabel succeeded."
    fi
}

do_action_internal_main "$@"