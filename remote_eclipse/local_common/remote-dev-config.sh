#! /bin/bash
#
# remote-dev-config.sh -- Configuration for remote building and deployment
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

### BEGIN INCLUDE GUARD ###
if [[ "${REMOTE_DEV_CONFIG_SOURCED}" == "true" ]]; then
    return
fi
export REMOTE_DEV_CONFIG_SOURCED=true
### END INCLUDE GUARD ###

source common-functions.sh

config_resource()
{
    if [[ -z "$1" ]]; then
        return 0
    fi

    getBuildConfigInfo "$1"
}

getBuildConfigInfo()
{
    export ACTIVECONFIG=
    if [[ -n "$CONFIGNAME" ]]; then
        ACTIVECONFIG="$CONFIGNAME"
    else
        getActiveConfigurationName ACTIVECONFIG
    fi

    # Note: any variable listed here WILL be defined, after the call,
    # even if not found (they will be therefore blank).
    project_export REMOTEDEPLOYUSER REMOTEDEPLOYHOST \
        REMOTEHDRPATHS LOCALHDRCACHE

    getRemoteResourcePaths "$1"

    return
}


getRemoteResourcePaths()
{
    # ------------------------------------------------
    # Interpretting first argument (file)
    # ------------------------------------------------
    srcunix="${1#/$PROJECT_NAME}"
    if [[ "$srcunix" != "$1" ]]; then
        srcunix="${PROJECT_PATH}${srcunix}"
    fi

    # To get the sub-project name, strip off the leading slash, then all
    # the trailing slashes.  This is the top-level folder within the project.
    subprojname="${srcunix#$PROJECT_PATH}"
    subprojname="${subprojname#/}"
    subprojname="${subprojname%%/*}"
    # If the subprojname is really just a file in the in top-level folder,
    # we should try
    if [[ -z "$subprojname" ]] || [[ ! -d "$PROJECT_PATH/$subprojname" ]]; then
        subprojname="."
    fi

    # Let's see if the sub-project doesn't have a build script.  if so,
    # go up to the parent.
    if [[ "$subprojname" != "." ]]; then
        local multiActionScript=
        find_multi_action_script multiActionScript "$subprojname"

        if [[ ! -e "$multiActionScript" ]]; then
            local multiActionScript=
            find_multi_action_script multiActionScript "."
            if [[ -e "$multiActionScript" ]]; then
                srcunix="${PROJECT_PATH}"
                subprojname="."
            fi
        fi
    fi

    # Adding a variable to represent the resource we are
    # actually building, and stripping the project name if
    # we are building the top-level project as a whole
    build_resource="/$PROJECT_NAME/$subprojname"
    build_resource="${build_resource%/.}"
}
