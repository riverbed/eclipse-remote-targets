#! /bin/bash
#
# common-functions.sh -- Common functions shared across scripts
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source local-remote-common.sh

### BEGIN INCLUDE GUARD ###
if [[ "${COMMON_FUNCTIONS_SOURCED}" == "true" ]]; then
    return
fi
export COMMON_FUNCTIONS_SOURCED=true
### END INCLUDE GUARD ###

export CONFIG_DATA_PROVIDER=

# Universal target for launching a shell
export REMOTE_SHELL_TARGET_NAME="remote shell"

# Remove all legacy path escaping before any local action
remove_path_variable_legacy_escaping

# By default assume we are not in a setup project.  Other users may override
# this library with their own function that returns true
inSetupProject()
{
    false
}

enable_debug_release_project()
{
    export PROJECT_TYPE="xconf"
    export ENABLEDEBUGBUILD="DebugRelease"
    export PAUSE_AT_END_ON_UPDATE="false"
    export REMOTEDEPLOYHOST="none"
}
    
is_debug_release_project()
{
    [[ "$ENABLEDEBUGBUILD" == "DebugRelease" ]]
}

getProjectLocation()
{
    local varname=$1
    local _projname=$2

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi
    if [[ -z "${_projname}" ]]; then
        exit_with_error "$FUNCNAME: Must supply project name."
    fi

    local searchString="URI//file:"
    local propPath=".metadata/.plugins/org.eclipse.core.resources/.projects"
    local projPath="$WORKSPACE_PATH/$propPath/${_projname}"
    local propFile="$projPath/.location"

    #
    local result

    if [[ ! -e "$projPath" ]]; then
        # No project path at all in metdata, thus, it doesn't exist.
        result=""
    elif [[ ! -e "$propFile" ]]; then
        # There is a path for this project, but no location specified, so it
        # must be the default (within the workspace)
        if [[ "${WORKSPACE_LOC:0:1}" == "/" ]]; then
            result="$WORKSPACE_LOC/${_projname}"
        else
            result="$WORKSPACE_LOC\\${_projname}"
        fi
    else
        # We have a path inside
        result="$(cat "$propFile" | LANG='' tr '\0' '\n' | \
                grep --text "${searchString}" | \
                head -n 1 | \
                sed "s|.*${searchString}||")"

        result="$(printf '%b' "${result//\%/\x}")"

        case "$result" in
            /[A-Z]:/*)
                result="${result:1}"
                result="${result//\//\\}"
                ;;
        esac

        #result="$(cd "$result" && pwd)"
    fi

    eval "$varname=\"$result\""
}

setConfigurationDataProvider()
{
    # This is needed only if you are using an old-style external tool
    # and thus the detected project is the Remote Targets project itself.
    if [[ "$PROJECT_NAME" == "remote_eclipse" ]]; then
        suppress_error_line_numbers
        exit_with_error "Change current focus to a resource within a" \
            "C++ project prior to selecting this external tool."
    fi

    if [[ -z "${CONFIG_DATA_PROVIDER}" ]]; then
        local searchString="configurationDataProvider."
        local propPath=".metadata/.plugins/org.eclipse.core.resources/.projects"
        local projPath="$WORKSPACE_PATH/$propPath/$PROJECT_NAME"
        local propFile="$projPath/.indexes/properties.index"

        local result=
        if [[ -e "$propFile" ]]; then
            result="$(cat "$propFile" | LANG='' tr '\0' '\n' | \
                grep --text "${searchString//./\\.}" | \
                head -n 1 | \
                sed "s#\(.*\)\(${searchString//./\\.}\)\([0-9][.0-9]*\).*#\3#")"
        else
            # No property file.
            if [[ -e "$projPath" ]] || ! inSetupProject; then
                exit_with_error "Can't find properties file for" \
                    "'$PROJECT_NAME', it must have been deleted and" \
                    "we and not in setup project mode."
            else
                # If there is no project path at all, then the
                # project has been deleted, so we should use the default config.
                :
            fi
        fi

        if [[ -n "$result" ]]; then
            # If we have an active configuration, use it.
            CONFIG_DATA_PROVIDER="$result"
            return
        fi

        # No active configuration data provider, so we should find the default
        # one in the cProject File.  The default will be the first one found.
        local cprojectFile="$PROJECT_PATH/.cproject"

        if [[ ! -e "$cprojectFile" ]]; then
            exit_with_error "Can't find .cproject file for '$PROJECT_NAME'"
        fi

        result="$(grep "${searchString//./\\.}" "$cprojectFile" | \
            head -n 1 | \
            sed "s#\(.*\)\(${searchString//./\\.}\)\([0-9][.0-9]*\).*#\3#")"

        if [[ -z "$result" ]]; then
            exit_with_error "No configuration data provider detected"
        fi

        CONFIG_DATA_PROVIDER="$result"
    fi
}

universal_local_config()
{
    export LOCALPROJECTNAME="${PROJECT_NAME}"
    export LOCALPROJECTDIR="${PROJECT_PATH}"

    project_export REMOTEPROJECTDIR REMOTEBUILDUSER REMOTEBUILDHOST

    if [[ -z "$REMOTEPROJECTDIR" ]]; then
        project_export REMOTEBUILDHOME REMOTEPROJECTNAME

        if [[ -z "$REMOTEPROJECTNAME" ]]; then
            # This is for really old projects that don't yet have this variable
            exit_with_error "REMOTEPROJECTNAME not defined. Re-run" \
             "setup for this project."
        fi

        if [[ -z "$REMOTEBUILDHOME" ]]; then
            # For old projects, there is no REMOTEBUILDHOME defined in the
            # configuration, so assume it's like on the focus boxes /home/user.
            REMOTEBUILDHOME=/home/$REMOTEBUILDUSER
        fi
        export REMOTEPROJECTDIR=$REMOTEBUILDHOME/$REMOTEPROJECTNAME
    fi
    export BINDEV=$REMOTEPROJECTDIR/.remoteEclipse/bindev
    export RWSDIR=$REMOTEPROJECTDIR/.remoteEclipse/workspace
    export REMOTEPROJECTDOTDOT=${REMOTEPROJECTDIR%/*}
}

getProjectSaveCount()
{
    local varname=$1

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi
    
    local searchString="configurationDataProvider."
    local propPath=".metadata/.plugins/org.eclipse.core.resources/.projects"
    local projPath="$WORKSPACE_PATH/$propPath/$PROJECT_NAME"
    
    if [[ ! -e "$projPath" ]]; then
        exit_with_error "$FUNCNAME: Project path '$projPath' could not be found"
    fi

    local result="$(find "${projPath}" -name "*.tree" | sort -u | tail -n 1)"
    if [[ -n ${result} ]]; then
        result="${result##*/}"
        result="${result%.tree}"
    else
        result=0
    fi
    
    eval "$varname='${result}'"
}

getActiveConfigurationName()
{
    local varname=$1

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    # If not previously set, set the configuration data provider.
    setConfigurationDataProvider

    # No active configuration data provider, so we should find the default
    # one in the cProject File.  The default will be the first one found.
    local cprojectFile="$PROJECT_PATH/.cproject"
    local search1="<storageModule buildSystemId"
    # Make sure also to add a final quote and space to the configuration
    # data provider because they are numbers separated by dots and without
    # something after the dotted numbers, we could hit on the first partial
    # match and return the wrong configuration name.
    local search2="configurationDataProvider.${CONFIG_DATA_PROVIDER}\"[ ]"

    if [[ ! -e "$cprojectFile" ]]; then
        exit_with_error "Can't find .cproject file for '$PROJECT_NAME'"
    fi

    result="$(grep "${search1}.*${search2/./\\.}" "$cprojectFile" | \
        head -n 1 | \
        sed "s#.*[ ]name=\"\(.*\)\">.*#\1#" )"

    if [[ -z "$result" ]]; then
        exit_with_error "No active configuration found"
    fi
    eval "$varname=\"$result\""
}

project_export()
{
    local forceReadFromFile=false
    local noOverride=false
    while [[ "${1#-}" != "${1}" ]]; do
        case $1 in
            -f|--force)
                forceReadFromFile=true
                ;;
            -n|--no-override)
                noOverride=true
                ;;
        esac
        shift
    done

    # First see if we are in a context where the project is defined, by
    # looking to see if CONFIGNAME is defined.
    if [[ ${!CONFIGNAME[@]} ]]; then
        # OK, We are in an active project.  We should probably bail here
        # unless the force switch is turned on, and thus we'll replace
        # local enviornment variables from the preferences file.
        if [[ "$forceReadFromFile" == "false" ]]; then
            return 0
        fi
    fi
    local varname
    for varname in $*; do
        # Get the variable if we aren't in no-override mode, or if the variable doesn't exist already
        if [[ $noOverride == false ]] || [[ -z "$(eval echo "\${!$varname[@]}")" ]]; then
            getVariableFromProject $varname
            # Make sure we are exporting any variables from the project
            eval "export $varname"
        fi
    done
}

hasConfigurationProvider()
{
    if   [[ -e "$PROJECT_PATH/.cproject" ]] && \
         [[ -e "$PROJECT_PATH/.settings/org.eclipse.cdt.core.prefs" ]]; then
        true
    else
        false
    fi
}

getVariableFromProject()
{
    # If not previously set, set the configuration data provider.
    setConfigurationDataProvider

    local outvarname
    local varname
    if [[ "$1" == "-to" ]]; then
        shift
        # Store the project variable in
        outvarname=$1
        shift
        varname=$1
    else
        # Output variable name is the same as the project variable name
        outvarname=$1
        # do not shift, varname is also $1
        varname=$1
    fi

    if [[ -z "$varname" ]] || [[ -z "$outvarname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    local default="$2"

    local prefix="configurationDataProvider.${CONFIG_DATA_PROVIDER}"
    local search="/$varname/value="

    local prefsPath="$PROJECT_PATH/.settings"
    local prefsFile="$prefsPath/org.eclipse.cdt.core.prefs"

    if [[ ! -e "$prefsFile" ]]; then
        exit_with_error "Can't find preferences file for '$PROJECT_NAME'"
    fi

    local line="$(grep "${prefix//./\\.}${search}" "$prefsFile" | tr -d '\n\r')"

    if [[ -n "$line" ]]; then
        line="${line#*/$varname/value=}"
        line=${line//\\=/=}
        eval "$outvarname='${line#*/$varname/value=}'"
        return 0
    else
        eval "$outvarname='$default'"
        return 1
    fi
}

saveVariableToProject()
{
    saveVariablesToProject "$@"
}

saveVariablesToProject()
{
    # If not previously set, set the configuration data provider.
    setConfigurationDataProvider

    local allConfigs=false
    if [[ "$1" == "-allConfigs" ]]; then
        allConfigs=true
        shift
    elif [[ "$1" == "-activeConfig" ]]; then
        allConfigs=false
        shift
    else
        exit_with_error "$FUNCNAME: Must supply either -allConfigs or" \
            "-activeConfig as the first parameter."
    fi
    if [[ -z "$1" ]]; then
        exit_with_error "$FUNCNAME: Must supply at least one variable name."
    fi

    local sedexp=
    while [[ -n "$1" ]]; do
        local invarname=
        local varname=
        if [[ "$1" == "-from" ]]; then
            shift
            # Store the project variable in
            invarname=$1
            shift
            varname=$1
            shift
        else
            # Input variable name is the same as the project variable name
            invarname=$1
            # do not shift, varname is also $1
            varname=$1
            shift
        fi

        if [[ -z "$varname" ]] || [[ -z "$invarname" ]]; then
            exit_with_error "$FUNCNAME: Must supply variable name."
        fi

        local prefix="configurationDataProvider."
        local search="/$varname/value="
        if [[ "$allConfigs" == "true" ]]; then
            search="[0-9][\\.0-9]*${search}"
        else
            prefix="${prefix}${CONFIG_DATA_PROVIDER}"
        fi

        local prefsPath="$PROJECT_PATH/.settings"
        local prefsFile="$prefsPath/org.eclipse.cdt.core.prefs"

        if [[ ! -e "$prefsFile" ]]; then
            exit_with_error "Can't find preferences file for '$PROJECT_NAME'"
        fi

        # Does the in-variable name exist?
        if [[ -n "$(eval echo "\${!$invarname[@]}")" ]]; then
            # Yes it does, so get the value and set it.
            local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$invarname)"

            varvalue="${varvalue//\\/\\\\\\\\}"
            varvalue="${varvalue//\"/\\\"}"
            varvalue="${varvalue//@/\\@}"
            varvalue="${varvalue//=/\\\\=}"

            sedexp="${sedexp};s@\(${prefix//./\\.}${search}\).*@\1$varvalue@"
        else
            # The variable was not even set, so interpret that as remove it.
            sedexp="${sedexp};\\@\(${prefix//./\\.}${search%value=}\).*@d"
        fi
    done
    sedexp="${sedexp:1}"
    sedInPlace "$sedexp" "$prefsFile"
}

getVariableFromFile()
{
    local varname=$1
    local file="$2"
    local default="$3"

    if [[ -e "$file" ]]; then
        eval "$varname=\"$(< "$file")\""
    else
        eval "$varname=\"$default\""
    fi
    # To properly handle the case where the value is -e,
    # we use POSIXLY_CORRECT and /bin/echo to make sure it
    # does the right thing.
    #echo $varname is now "$(eval POSIXLY_CORRECT=1 echo \$$varname)"
}

saveVariableToFile()
{
    local varname=$1
    local file="$2"
    # To properly handle the case where the value is -e,
    # we use POSIXLY_CORRECT and /bin/echo to make sure it
    # does the right thing.
    local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"
    if [[ -n "$varvalue" ]]; then
        POSIXLY_CORRECT=1 /bin/echo "$varvalue" > "$file"
    elif [[ -e "$file" ]]; then
        rm -f "$file"
    fi
}

git_assume_unchanged_if_not_ignored()
{
    while [[ -n "$1" ]]; do
        if [[ -e "$1" ]] && ! grep -q "${1//./\\.}" .gitignore; then
            git update-index --skip-worktree --assume-unchanged "$1"
        fi
        shift
    done
}

git_no_assume_unchanged_if_not_ignored()
{
    while [[ -n "$1" ]]; do
        if [[ -e "$1" ]] && ! grep -q "${1//./\\.}" .gitignore; then
            # This file exists and isn't in the ignore file, so let's
            # reset the assume unchanged setting.
            git update-index --no-skip-worktree --no-assume-unchanged "$1"
            git checkout HEAD -- "$1"
        elif [[ -e "$1" ]] && grep -q "${1//./\\.}" .gitignore; then
            # This file/folder exists and is being ignored, so we
            # should remove it 
            rm -rf "./$1"
        fi
        shift
    done
}

setup_project_ignore_files()
{
    pushd "$PROJECT_PATH" >& /dev/null

    # If repository is git, and not a git/SVN bridge
    if [[ -e .gitignore ]] && [[ ! -e .svn ]]; then
        git_assume_unchanged_if_not_ignored .cproject .project .settings
    fi

    popd >& /dev/null
}

unsetup_project_ignore_files()
{
    pushd "$PROJECT_PATH" >& /dev/null

    # If repository is git, and not a git/SVN bridge
    if [[ -e .gitignore ]] && [[ ! -e .svn ]]; then
        git_no_assume_unchanged_if_not_ignored .cproject .project .settings

        # Find out if the project has been deleted or closed. An empty string
        # would imply it was deleted.
        local projectLoc=""
        getProjectLocation projectLoc "$PROJECT_NAME"

        # In Eclipse Neon, completing removing the .settings folder will
        # result in PATH is null (literally the word) bug.  A workaround is
        # to create a mostly empty .settings folder, having just an empty
        # org.eclipse.cdt.core.prefs file.  NOTE: This only needs to be done
        # if the project is closed during an unsetup.  If it is actually
        # deleted, then this isn't necessary.
        if [[ -n "$projectLoc" ]] && [[ ! -e .settings ]]; then
            mkdir .settings
            touch .settings/org.eclipse.cdt.core.prefs
        fi
    fi

    popd >& /dev/null
}

rSyncSupportsMultipleSources()
{
    local versionLine=$(rsync --version | head -n 1)

    if [[ "$versionLine" != "${versionLine/version 2./}" ]]; then
        false
    else
        true
    fi
}

update_header_cache()
{
    # Make sure REMOTEHDRPATHS has no legacy escaping
    verify_no_legacy_escaped_path_variables
    # Change all semicolons to colons
    local remoteih="${REMOTEHDRPATHS//;/:}"
    local exclusionargs="--include='*/'"
    exclusionargs="$exclusionargs --include='*.h'"
    exclusionargs="$exclusionargs --include='*.H'"
    exclusionargs="$exclusionargs --include='*.hh'"
    exclusionargs="$exclusionargs --include='*.hpp'"
    exclusionargs="$exclusionargs --include='*.hxx'"
    exclusionargs="$exclusionargs --include='*.c'"
    exclusionargs="$exclusionargs --include='*.C'"
    exclusionargs="$exclusionargs --include='*.cc'"
    exclusionargs="$exclusionargs --include='*.cpp'"
    exclusionargs="$exclusionargs --include='*.cxx'"
    exclusionargs="$exclusionargs --include='*.tcc'"
    exclusionargs="$exclusionargs --include='*.x'"
    exclusionargs="$exclusionargs --include='*.api'"
    exclusionargs="$exclusionargs --include='*.cfg'"
    exclusionargs="$exclusionargs --include='*.def'"
    exclusionargs="$exclusionargs --include='*.inl'"
    exclusionargs="$exclusionargs --include='*.ipp'"
    exclusionargs="$exclusionargs --include='*.uil'"
    exclusionargs="$exclusionargs --exclude='*.*'"
    local status=

    # Make sure LOCALHDRCACHE has no legacy escaping
    verify_no_legacy_escaped_path_variables

    echo
    echo "Caching all system headers and debug sources from remote system..."
    if rSyncSupportsMultipleSources && [[ "$remoteih" == "${remoteih// /}" ]]; then
        local allremotepaths="$REMOTEBUILDUSER@$REMOTEBUILDHOST:${remoteih//:/ :}"
        eval "rsync -q --relative --copy-links -rtvz -e ssh --delete" \
            "$exclusionargs" \
            "--chmod Du+w,Fa-w --perms --no-g --no-o $allremotepaths" \
            "'${REMOTE_ECLIPSE_PATH%/*}/${LOCALHDRCACHE#/}'"
        status=$?
    else
        local includeHeaderPath
        IFS=":"
        for includeHeaderPath in $remoteih; do
            local escIncludeHeaderPath="${includeHeaderPath}"
            escIncludeHeaderPath="${escIncludeHeaderPath// /\\ }"
            escIncludeHeaderPath="${escIncludeHeaderPath//(/\\(}"
            escIncludeHeaderPath="${escIncludeHeaderPath//)/\\)}"
            eval "rsync -q --relative --copy-links -rtvz -e ssh --delete" \
                "$exclusionargs" \
                "--chmod Du+w,Fa-w --perms --no-g --no-o" \
                "'$REMOTEBUILDUSER@$REMOTEBUILDHOST:${escIncludeHeaderPath}'" \
                "'${REMOTE_ECLIPSE_PATH%/*}/${LOCALHDRCACHE#/}'"
            status=$?
            if [[ $status != 0 ]]; then
                break
            fi
        done
        unset IFS
    fi
    if [[ $status == 0 ]]; then
        echo "Inbound cache rsync completed."
    else
        echo "Inbound cache rsync failed."
    fi
    return $status
}

remote_build_uses_gcc()
{
    local _compiler="${INDEXER_CXX_COMPILER:-g++}"
    [[ "${_compiler}" != "${_compiler%g++}" ]]
}

export_all_functions
