#! /bin/bash
#
# setup-project.sh -- choose from a menu of project types and instantiate one
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# Header files
source common-functions.sh

# Path to scripts and templates for extended (non-built-in) projects
PROJECT_EXTENSION_PATH="$REMOTE_ECLIPSE_PATH/template_extensions"

is_ipv4_address()
{
    # An IPv4 address won't have any letters in it (nor a colon)
    echo $1 | grep -v -q "[:a-zA-Z]"
}

add_source_location_exclusion_rules()
{
    while [[ -n "$1" ]]; do
        config1_sourceEntriesExcluding="${config1_sourceEntriesExcluding}
            $1
        "
        shift
    done
}

add_source_location_exclusion_rules_internal()
{
    local first=true
    local line=
    echo "$1" | \
    while read line; do
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ -z "$line" ]]; then
            continue
        fi
        if [[ $first == false ]]; then
            echo -n "|"
        else
            local first=false
        fi
        echo -n "$line"
    done
    echo
}

inSetupProject()
{
    # Override the implementation in common-functions.sh above
    true
}

isInSourceSetupProject()
{
    # We are an in-source setup (via a make target in a multi-action script)
    # if CONFIGNAME is already known and set.
    [[ -n "$CONFIGNAME" ]]
}


isProjectOpen()
{
    local saveCount=
    getProjectSaveCount saveCount
    
    # If the project save count has not changed, the project is still open
    [[ "$saveCount" == "$PROJECT_SAVE_COUNT" ]];
}

updateProgress()
{
    if [[ -n "$1" ]]; then
        echo
        if [[ -n "$PROGRESS_LABEL" ]]; then
            # We already had a label, so add an extra blank line
            echo
        fi
        PROGRESS_LABEL="$1"
        let PROGRESS_COUNTER=0
        shift
    else
        let PROGRESS_COUNTER=$PROGRESS_COUNTER+1
    fi
    printf "${PROGRESS_LABEL// /_}%${PROGRESS_COUNTER}s\r" | \
        tr " " "." | tr "_" " "
}

eval "original_$(declare -f sedInPlace)"
sedInPlace()
{
    original_sedInPlace "$@"
    updateProgress
}

# Make sure all setup project scripts define this so that
# we don't put prefixes in error messages
suppress_error_line_numbers

# trap Ctrl-C or Ctrl-Break
trap on_control_c_or_control_break INT
trap on_exit EXIT

on_exit()
{
    if [[ -d "$PROJECT_PATH" ]] && [[ -d "$PROJECT_PATH.bak" ]]; then
        pushd "$PROJECT_PATH.bak" >& /dev/null

        if [[ -e .cproject ]]; then
            cp .cproject "$PROJECT_PATH"
        else
            rm -f "$PROJECT_PATH/.cproject"
        fi
        if [[ -e .project ]]; then
            cp .project "$PROJECT_PATH"
        else
            rm -f "$PROJECT_PATH/.project"
        fi
        if [[ -d .settings ]]; then
            cp -Rf .settings "$PROJECT_PATH"
        else
            rm -rf "$PROJECT_PATH/.settings"
        fi
        popd >& /dev/null

        rm -rf "$PROJECT_PATH.bak"
    fi
}

on_control_c_or_control_break()
{
    echo
    echo
    show_error "*** Trapped $PLATFORM_BREAK_KEY. Exiting. ***"
    sleep 1
    kill -INT $$
    exit 1
}

echoConcatenatedStringNtimes()
{
    local char="$1"
    local n=$2
    local i

    local return_string=

    for (( i = 1; i <= $n; i++ )); do
        return_string="${return_string}${char}"
    done
    echo $return_string
    return
}

showBanner()
{
    local banner_string="$1"
    local pad_str="     "
    banner_string="${pad_str}${banner_string}${pad_str}"
    echoConcatenatedStringNtimes "=" ${#banner_string}
    echo "$banner_string"
    echoConcatenatedStringNtimes "=" ${#banner_string}
    echo
}

hasHeaderCache()
{
    if [[ -d "${REMOTE_ECLIPSE_PATH%/*}/$hdrcachepath" ]]; then
        # True, the header cache was found
        return 0
    else
        # False, the header cache was not found
        return 1
    fi
}

removeLegacyDotFilesForVariables()
{
    local varname
    for varname in $*; do
        #convert variable name to lowercase, prepended with a dot.
        local dotfile="$(echo .$varname | tr '[A-Z]' '[a-z]')"
        local fulldotfile="$LOCALPROJECTDIR/$dotfile"
        if [[ -e "$fulldotfile" ]]; then
            rm -f "$fulldotfile"
        fi
    done
}

removeLegacyDotFilesFromProject()
{
    # First test for the .remoteexists file, so if it's not seen, save time
    # and remove nothing.
    if  [[ -e "$LOCALPROJECTDIR/.remoteexists" ]] || \
        [[ -e "$LOCALPROJECTDIR/.activeconfig" ]] || \
        [[ -e "$LOCALPROJECTDIR/.testbasename" ]]; then
        rm -rf launches
        rm -rf .launches
        # The folder below is now deprecated and can be removed
        if [[ -d DeployBin ]]; then
            rm -r DeployBin
        fi

        removeLegacyDotFilesForVariables REMOTEBUILDUSER REMOTEBUILDHOST \
            REMOTEBUILDHOME REMOTEDEPLOYUSER REMOTEDEPLOYHOST EXECSW \
            COREFILE ENABLEDEBUGBUILD MAINBINARY ACTIVECONFIG \
            REMOTEPROJECTNAME MAINSUBPROJ REMOTEHDRPATHS LOCALHDRCACHE \
            REMOTEEXISTS TESTBASENAME TESTCONFIG
    fi
}

get_build_command()
{
    local varname="$1"
    shift

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    local _result="\"\${workspace_loc:remote_eclipse/local_os/\${system:OS}/build.bash}\""
    # Reuse -wl parameter to hide the version at setup since it will be safely ignored
    # by older versions of Eclipse for RT.  This is a backwards compatible way of
    # starting to serialize the version at setup inside Eclipse for RT projects
    _result="${_result} -env -wl ${ECLIPSE_RT_VERSION} -wl \"\${workspace_loc}\""
    _result="${_result} -pl \"\${workspace_loc:\${ProjName}}\""
    _result="${_result} -pn \"\${ProjName}\" -cn \"\${ConfigName}\""

    eval "$varname='${_result}'"
}

add_target()
{
    local targetLine=
    add_or_remove_target_internal -targetLineVar targetLine "$@"
    
    # Build up a list of targets, but don't actually do anything
    TARGET_LIST="${TARGET_LIST}${TARGET_LIST:+;}$targetLine"
}

remove_target()
{
    local targetLine=
    add_or_remove_target_internal -targetLineVar targetLine "$@"
    
    TARGET_LIST=";${TARGET_LIST};"
    TARGET_LIST="${TARGET_LIST//;$targetLine;/;}"
    TARGET_LIST="${TARGET_LIST#;}"
    TARGET_LIST="${TARGET_LIST%;}"
}

add_or_remove_target_internal()
{
    local targetName=""
    local targetPath=""
    local targetLineVar=""
    while [[ "${1#-}" != "$1" ]]; do
        curarg="$1"
        shift
        case $curarg in
            -targetLineVar*)
                targetLineVar="$1"
                shift
                ;;
            -targetName*)
                targetName="$1"
                shift
                ;;
            -targetPath*)
                targetPath="$1"
                shift
                ;;
            *)
                exit_with_error "$FUNCNAME: Unrecognized build target option."
                ;;
        esac
    done
    
    if [[ -z "$targetName" ]]; then
        exit_with_error "$FUNCNAME: Must supply build target name."
    fi
    if [[ -z "$targetLineVar" ]]; then
        exit_with_error "$FUNCNAME: Must supply build target line variable."
    fi
    eval "$targetLineVar='$targetPath|$targetName'"
}

add_universal_targets()
{
    # Add a target to launch a shell for each project
    add_target -targetName "${REMOTE_SHELL_TARGET_NAME}"
}

write_targets_to_project()
{
    # Sort the list by path, then by name (and remove duplicates)
    echo "${TARGET_LIST}" | tr ';' '\n' | sort -u -t\| -k 1,1 -k 2,2 | \
    while read targetLine; do
        # Left of | is path, right of | is name
        local targetPath="${targetLine%|*}"
        local targetName="${targetLine#*|}"
        write_target_internal "$targetPath" "$targetName"
    done
}

write_target_internal()
{
    local targetPath="$1"
    local targetName="$2"

    local targetBuildCmd
    get_build_command targetBuildCmd

    if [[ "$targetPath" == "." ]]; then
        targetPath=""
    fi

    local str=""
    str="${str}${_TAB}${_TAB}${_TAB}<target name=\"${targetName}\" path=\"${targetPath}\""
    str="${str} targetID=\"org.eclipse.cdt.build.MakeTargetBuilder\">_~_"
    str="${str}${_TAB}${_TAB}${_TAB}${_TAB}<buildCommand>bash</buildCommand>_~_"
    str="${str}${_TAB}${_TAB}${_TAB}${_TAB}<buildArguments>${targetBuildCmd}</buildArguments>_~_"
    str="${str}${_TAB}${_TAB}${_TAB}${_TAB}<buildTarget>${targetName}</buildTarget>_~_"
    str="${str}${_TAB}${_TAB}${_TAB}${_TAB}<stopOnError>true</stopOnError>_~_"
    str="${str}${_TAB}${_TAB}${_TAB}${_TAB}<useDefaultCommand>true</useDefaultCommand>_~_"
    str="${str}${_TAB}${_TAB}${_TAB}${_TAB}<runAllBuilders>true</runAllBuilders>_~_"
    str="${str}${_TAB}${_TAB}${_TAB}</target>_~_"

    local fileName="$PROJECT_PATH/.cproject"
    local tagName="buildTargets"
    local endMarker="${_TAB}${_TAB}</$tagName>"

    # If there has never been a buildTarget before, replace
    # the empty tag with two open/close tags, since we are about
    # to add a target in beteween
    if grep -q "$tagName/" "$fileName"; then
        prepend_text_in_file "$fileName" "${endMarker/\/$tagName/$tagName/}" \
            "${endMarker/\//}_~_"
        sedInPlace -e "s@<$tagName/>@</$tagName>@" "$fileName"
    fi
    # Now actually add the target to the end (before the close tag)
    prepend_text_in_file "${fileName}" "${endMarker}" "${str}"
}

add_refresh_scope_entry()
{
    local resourceType=""
    local workspacePath=""
    while [[ "${1#-}" != "$1" ]]; do
        curarg="$1"
        shift
        case $curarg in
            -resourceType*)
                resourceType="$1"
                shift
                ;;
            -workspacePath*)
                workspacePath="$1"
                shift
                ;;
            *)
                exit_with_error "$FUNCNAME: Unrecognized refresh scope option."
                ;;
        esac
    done
    
    if [[ -z "$resourceType" ]]; then
        exit_with_error "$FUNCNAME: Must supply resource type name."
    fi
    if [[ -z "$workspacePath" ]]; then
        exit_with_error "$FUNCNAME: Must supply workspace Path."
    fi

    local str=""
    str="${str}${_TAB}${_TAB}${_TAB}<resource resourceType=\"${resourceType}\" workspacePath=\"${workspacePath}\"/>_~_"

    local fileName="$PROJECT_PATH/.cproject"
    local tagName="configuration"
    local endMarker="^${_TAB}${_TAB}</$tagName>"
    
    # Now add the resource scope entry to the end (before the close tag)
    prepend_text_in_file "${fileName}" "${endMarker}" "${str}"
}

replace_config_source_exclusion_filter()
{
    local i
    let i=1
    local varname=config${i}_sourceEntriesExcluding
    while [[ -n "$(eval echo "\${!$varname[@]}")" ]]; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \"\$$varname\")"
        
        local  searchStr=" excluding=\"$varname\""
        local replaceStr=""

        if [[ -n "$varvalue" ]]; then
            # Replace separate lines with pipe (|) characters first... 
            varvalue="$(add_source_location_exclusion_rules_internal "$varvalue")"
            # ... then change all spaces in the variable to pipe (|) characters
            varvalue="${varvalue// /|}"
            replaceStr=" excluding=\"$varvalue\""
        fi

        replaceStr="${replaceStr//\\/\\\\\\\\}"
        replaceStr="${replaceStr//\"/\\\"}"
        replaceStr="${replaceStr//@/\\@}"

        sedInPlace "s@$searchStr@$replaceStr@g" .cproject

        let i=$i+1
        varname=config${i}_sourceEntriesExcluding
    done
}

replace_build_command()
{
    subprojname="$1"
    shift

    if [[ -z "$subprojname" ]]; then
        exit_with_error "$FUNCNAME: Must supply subprojname"
    fi

    local buildCommand
    get_build_command buildCommand

    local build_resource="/$PROJECT_NAME/${subprojname:-.}"
    build_resource="${build_resource%/.}"

    local srBuildSuffix="-sr \"\${selected_resource_path}\""
    local autoBuildTarget="${srBuildSuffix} -action save"
    local cleanBuildTarget="${srBuildSuffix} -action clean"
    local incrementalBuildTarget="${srBuildSuffix} -action incr"
    local buildPath="\${workspace_loc:${build_resource}}"
    local command="bash"

    local replace="\\1${buildCommand}\\2${autoBuildTarget}"
    replace="${replace}\\3${buildPath}\\4${cleanBuildTarget}"
    replace="${replace}\\5${command}\\6${incrementalBuildTarget}\\7"

    replace="${replace//\"/&quot;}"
    replace="${replace//@/\\@}"
    replace="${replace//&/\\&}"
    replace="${replace//=/\\\\=}"

    local search="\\(builder arguments=\"\\).*\\(\" autoBuildTarget=\"\\)"
    search="${search}.*\\(\" buildPath=\"\\)"
    search="${search}.*\\(\" cleanBuildTarget=\"\\)"
    search="${search}.*\\(\" command=\"\\)"
    search="${search}.*\\(\" enableAutoBuild=\".*\" incrementalBuildTarget=\"\\)"
    search="${search}.*\\(\" keepEnvironmentInBuildfile=\"\\)"

    sedInPlace "s@${search}@${replace}@g" ".cproject"

    if [[ ! -e .settings/language.settings.xml ]]; then
        return
    fi

    buildCommand="bash $buildCommand -sr \"\${INPUTS}\""
    buildCommand="$buildCommand -action get-compiler-specs"
    buildCommand="$buildCommand \${COMMAND} \${FLAGS} -E -P -v -dD"

    replace="${buildCommand}"
    replace="${replace//\"/&quot;}"
    replace="${replace//\\/\\\\\\\\}"
    replace="${replace//@/\\@}"
    replace="${replace//&/\\&}"
    replace="${replace//=/\\\\=}"

    search="\\(GCCBuiltinSpecsDetector.* parameter=\"\\).*\\(\" store-entries\\)"

    sedInPlace "s@${search}@\\1${replace}\\2@g" ".settings/language.settings.xml"

}

replace_config_names()
{
    local files=".cproject"
    if [[ -e .settings/language.settings.xml ]]; then
        files="$files .settings/language.settings.xml"
    fi

    local i
    let i=1
    local varname=config${i}_name
    while [[ -n "$(eval echo "\${!$varname[@]}")" ]]; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"

        varvalue="${varvalue//\\/\\\\\\\\}"
        varvalue="${varvalue//\"/\\\"}"
        varvalue="${varvalue//@/\\@}"

        sedInPlace "s@$varname@$varvalue@g" $files

        let i=$i+1
        varname=config${i}_name
    done
}

replace_c_flags_and_cxx_flags()
{
    local flagtypes="c_flags cxx_flags c_compiler cxx_compiler"

    # Lowercase version of the flag time
    local flagtype
    # Uppercase version of the flag time
    local FLAGTYPE
    for flagtype in $flagtypes; do
        local exp=""
        FLAGTYPE="$(echo $flagtype | tr '[a-z]' '[A-Z]')"
        FLAGTYPE="INDEXER_${FLAGTYPE}"
        local i
        let i=1
        local varname=config${i}_${flagtype}
        while [[ -n "$(eval echo "\${!$varname[@]}")" ]]; do
            local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"

            varvalue="${varvalue//\\/\\\\\\\\}"
            varvalue="${varvalue//\"/\\\"}"
            varvalue="${varvalue//@/\\@}"

            exp="$exp;s@/$FLAGTYPE/value=$varname@/$FLAGTYPE/value=$varvalue@g"

            let i=$i+1
            varname=config${i}_${flagtype}
        done
        exp="${exp:1}"
        # Do this replacement in the inner loop to prevent the sed expression from
        # being too large for BSD sed.
        sedInPlace "$exp" .settings/org.eclipse.cdt.core.prefs
    done
}

add_project_type()
{
    local newProjectCode=""
    local newProjectLabel=""
    local newProjectExtension=""
    while [[ "${1#-}" != "$1" ]]; do
        curarg="$1"
        shift
        case $curarg in
            -code)
                newProjectCode="$1"
                shift
                ;;
            -label)
                newProjectLabel="$1"
                shift
                ;;
            -extension)
                newProjectExtension="$1"
                shift
                ;;
            *)
                exit_with_error "$FUNCNAME: Unrecognized project option."
                ;;
        esac
    done
    if [[ -z "$newProjectCode" ]]; then
        exit_with_error "$FUNCNAME: No project code supplied"
    fi
    if [[ -z "$newProjectLabel" ]]; then
        newProjectLabel="$newProjectCode Project"
    fi
    let PROJECT_TYPE_MAX=${PROJECT_TYPE_MAX:-0}+1
    eval "PROJECT_NUM_${PROJECT_TYPE_MAX}_CODE='$newProjectCode'"
    eval "PROJECT_NUM_${PROJECT_TYPE_MAX}_LABEL='$newProjectLabel'"
    eval "PROJECT_NUM_${PROJECT_TYPE_MAX}_EXTENSION='$newProjectExtension'"
}

register_project_types()
{
    add_project_type -code "hw" -label "Hello World Project"
    
    if [[ ! -d "${PROJECT_EXTENSION_PATH}" ]]; then
        return
    fi
    
    pushd "$PROJECT_EXTENSION_PATH" &> /dev/null
    local extensionScript=
    for extensionScript in $(find . -name register-project-ext-*.sh); do
        source "$extensionScript"
    done
    popd &> /dev/null
}

choose_project_type()
{
    if [[ -n "$PROJECT_TYPE" ]]; then
        # Externally configured projects have the project code already defined
        PROJECT_CODE=$PROJECT_TYPE
        return
    fi
    
    register_project_types

    clear
    showBanner "Remote Eclipse Project Setup"

    local num=0;
    while [[ $num -lt ${PROJECT_TYPE_MAX} ]]; do
        let num=$num+1
        local label=
        eval "label=\"\${PROJECT_NUM_${num}_LABEL}\""
        echo "$num) $label"
    done
    echo

    local projnum=
    PROJECT_CODE=
    PROJECT_EXTENSION=

    while [[ -z "${PROJECT_CODE}" ]]; do
        read -p "Which project type? (1-${PROJECT_TYPE_MAX}, 0 to quit): " projnum
        case $projnum in
            ''|*[!0-9]*)
                # Empty string or not a number
                continue
                ;;
            *)
                # Is a number.  Normalize any trailing zeros
                let projnum=${projnum}
                ;;
        esac
        if [[ $projnum == 0 ]]; then
            exit 1
        elif [[ $projnum -le ${PROJECT_TYPE_MAX} ]]; then
            eval "PROJECT_CODE=\"\${PROJECT_NUM_${projnum}_CODE}\""
            eval "PROJECT_EXTENSION=\"\${PROJECT_NUM_${projnum}_EXTENSION}\""
        fi
    done
    
    if [[ -n "${PROJECT_EXTENSION}" ]]; then
        local extSetupScript="$PROJECT_EXTENSION_PATH/setup-project-ext-${PROJECT_EXTENSION}.sh"
        if [[ ! -e "$extSetupScript" ]]; then
            pause_and_exit_with_error "Project Extension Script '$extSetupScript' not found."
        fi
        # Import any extension functions
        source "$extSetupScript"
    fi

    return
}

get_prompt_to_change_platform()
{
    prev_remote_platform="${prevlocalhdrcache##*/}"

    if    [[ "$promptToChangePlatform" == "true" ]] && \
          [[ -n "${prev_remote_platform}" ]]; then
        echo
        echo "Previous platform label was ${prev_remote_platform}"
        echo
        local yes_or_no=
        local theprompt="Prompt to update it if no change detected? [no]: "
        read -p "$theprompt" yes_or_no

        if  [[ "${yes_or_no:0:1}" != "y" ]] && \
            [[ "${yes_or_no:0:1}" != "Y" ]]; then
            promptToChangePlatform=false
        fi
    fi
}


get_prompt_to_pause_on_finished_update()
{
    if     [[ "$promptToChangePlatform" != "true" ]] &&
           [[ "$pauseAtEndOnUpdate"     == "true" ]]; then
        echo
        local yes_or_no=
        local theprompt="Pause at end of project update? [no]: "
        read -p "$theprompt" yes_or_no

        if  [[ "${yes_or_no:0:1}" != "y" ]] && \
            [[ "${yes_or_no:0:1}" != "Y" ]]; then
            pauseAtEndOnUpdate=false
        fi
    fi
}
get_remote_platform()
{
    #echo buildhfp is [$buildhfp]
    #echo remoteos is [$remoteos]
    #echo remoteht is [$remoteht]
    #echo remotehn is [$remotehn]
    #echo remoterv is [$remoterv]
    #echo remoteih is [$remoteih]
    #echo remotecv is [$remotecv]

    local shortremoteos="$remoteos"
    
    if [[ "$remoteos" == "linux-gnu" ]]; then
        shortremoteos=linux
    fi

    # Get the remote hostname form the build host (stripping off domain)
    # in lowercase, and changing dashes to underscores (since dashes cause
    # issues in paths for Eclipse's discovery of build output due to a bug)
    remotehn=$(echo ${buildhst%%.*} | tr '[A-Z]' '[a-z]' | tr '-' '_' | tr ':' '_')

    if is_ipv4_address $buildhst; then
        # For IPv4 addresses, let's just turn all the dots to underscores
        # and not strip at the first dot (as we did above)
        remotehn=$(echo ${buildhst} | tr '.' '_')
    fi

    if [[ "$shortremoteos" == "FreeBSD" ]]; then
        def_remote_platform="${shortremoteos}_${remoterv:0:3}_${remotecv}_${remotehn}"
    elif [[ "$shortremoteos" == "cygwin" ]]; then
        def_remote_platform="${shortremoteos}_${remotecv}_${remotehn}"
    else
        def_remote_platform="${shortremoteos}_${remoteht}_${remotecv}_${remotehn}"
    fi

    prev_remote_platform="${prevlocalhdrcache##*/}"

    if [[ -n "${prev_remote_platform}" ]]; then
        if [[ "${def_remote_platform}" != "${prev_remote_platform}" ]]; then
            echo "Detected remote platform is ${def_remote_platform} ..."
            echo
            promptToChangePlatform=true
        else
            def_remote_platform="${prev_remote_platform}"
        fi
    fi

    remote_platform=
    if [[ "$promptToChangePlatform" == "true" ]]; then
        read -p "Remote platform label [${def_remote_platform}]: " \
            remote_platform
    fi
    if [[ -z "${remote_platform}" ]]; then
        remote_platform=${def_remote_platform}
    fi
}

getHeaderCacheLocation()
{
    echo
    echo "remote header paths for ${remote_platform}:"
    echo
    echo "${remoteih}" | tr ':' '\n'

    remotehp="${remoteih//:/;}"
    hdrcachepath="${headercacheprj}/${remote_platform}"
    lochdrcache="/${hdrcachepath}"
    verify_no_legacy_escaped_path_variables
}

setup_common_variables()
{
    #Index per folder for all projects (for now)
    perResourceScope=per-folder
    # sniemczyk: 2014-11-22: We need to index all versions of certain headers
    # for proper indexing, such as queue.h
    allVersionSpecificHeaders="queue.h"
    local common_flags="-Dlint -DCODAN"

    config1_name=Default
    # If INDEXER_C_FLAGS or INDEXER_CXX_FLAGS are defined, use that
    # instead of the common_flags above.
    config1_c_flags="${INDEXER_C_FLAGS-${common_flags}}"
    config1_cxx_flags="${INDEXER_CXX_FLAGS-${common_flags}}"
    config1_c_compiler="${INDEXER_C_COMPILER-gcc}"
    config1_cxx_compiler="${INDEXER_CXX_COMPILER-g++}"
    config1_sourceEntriesExcluding=""
}

setup_xconf_variables_and_targets()
{
    setup_hw_variables_and_targets
}

setup_hw_variables_and_targets()
{
    setup_subproject_variables_and_targets "$mainsubproj"
}

setup_default_subproject_variables_and_targets()
{
    local subprojname="$1"
    shift

    if [[ -z "$subprojname" ]]; then
        exit_with_error "$FUNCNAME: Must supply subprojname"
    fi

    add_target -targetPath $subprojname -targetName "build"
    add_target -targetPath $subprojname -targetName "clean"
    add_target -targetPath $subprojname -targetName "clean build"
    add_target -targetPath $subprojname -targetName "setup"
}

setup_subproject_variables_and_targets()
{
    local subprojname="$1"
    shift

    if [[ -z "$subprojname" ]]; then
        exit_with_error "$FUNCNAME: Must supply subprojname"
    fi
    
    if is_debug_release_project; then
        config1_name=Debug
        config2_name=Release
        
        local configN_c_flags="${config1_c_flags}"
        local configN_cxx_flags="${config1_cxx_flags}"
        local configN_c_compiler="${config1_c_compiler}"
        local configN_cxx_compiler="${config1_cxx_compiler}"
        local configN_sourceEntriesExcluding="${config1_sourceEntriesExcluding}"

        config1_c_flags="${configN_c_flags}"
        config2_c_flags="${configN_c_flags}"

        config1_cxx_flags="${configN_cxx_flags}"
        config2_cxx_flags="${configN_cxx_flags}"

        config1_c_compiler="${configN_c_compiler}"
        config2_c_compiler="${configN_c_compiler}"

        config1_cxx_compiler="${configN_cxx_compiler}"
        config2_cxx_compiler="${configN_cxx_compiler}"

        config1_sourceEntriesExcluding="${configN_sourceEntriesExcluding}"
        config2_sourceEntriesExcluding="${configN_sourceEntriesExcluding}"
    fi

    local multiActionScript=
    find_multi_action_script multiActionScript $subprojname

    local status=$ACTION_NOT_IMPLEMENTED

    # Try first to find a rule via the multi-action script
    if [[ -e "$multiActionScript" ]]; then
        pushd "$PROJECT_PATH/$subprojname" >& /dev/null
        source "$multiActionScript" -variables-and-targets
        status="$?"
        popd >& /dev/null
    fi

    if [[ $status == $ACTION_NOT_IMPLEMENTED ]]; then
        setup_default_subproject_variables_and_targets $subprojname
    fi
}

setup_xconf_project()
{
    local subprojname="${PWD#${PROJECT_PATH}/}"
    if [[ "$PWD" == "${PROJECT_PATH}" ]]; then
        subprojname="."
    fi

    if [[ -z "$BANNER_LABEL" ]]; then
        BANNER_LABEL=Externally Configured
    fi
    projtemplate=LocalProjectNameHW
    if is_debug_release_project; then
        projtemplate=LocalProjectNameH2
    fi
    tmplmainsubproj=ZzModuleName
    # Must set this to non-null for it to think this project uses this variable
    defmainsubproj=$subprojname
    # This is the value it will use if there wasn't a previously stored one.
    prevmainsubproj=$subprojname
    prevbuildopts=$CUSTOM_BUILD_OPTS
    # Default tab character is a space
    tabulationChar=${EDITOR_TAB_CHAR:-space}
    usescvs=false
}

setup_hw_project()
{
    defprojname=hello_world
    tmplmainsrcfile=mainsrcfile.cqq
    tmplcppext=cqq
    tmplhppext=hqq
    BANNER_LABEL="Hello World"
    projtemplate=LocalProjectNameH2
    tmplmainsubproj=ZzModuleName
    defmainsubproj=.
    sourceFiles="README.adoc"
    sourceFiles="$sourceFiles $tmplmainsubproj/CMakeLists.txt"
    sourceFiles="$sourceFiles $tmplmainsubproj/$tmplmainsrcfile"
    sourceFiles="$sourceFiles $tmplmainsubproj/remote_eclipse_build.sh"
    sourceFiles="$sourceFiles docs.doxyfile"
    sourceFiles="$sourceFiles docs.html"
    usescvs=false
    prevbuildopts=
    enable_debug_release_project
}

import_legacy_user_preferences()
{
    # Test if there are any of the old preferences saved, and if so, bring
    # them to their new location.
    if [[ -e "$REMOTE_ECLIPSE_PATH/.lastbuildhst" ]]; then
        # Look for legacy .last files, and move them to the new location.
        local lastFile
        find "$REMOTE_ECLIPSE_PATH" -name ".last*" | \
        while read lastFile; do
            mv "$lastFile" "$USER_PREFS_FOLDER/${lastFile##*.last}"
        done
    fi
}

setup_project_generic()
{
    templateloc="$PROJECT_EXTENSION_PATH/$projtemplate"
    if [[ ! -d "$templateloc" ]]; then
        templateloc="$REMOTE_ECLIPSE_PATH/template/$projtemplate"
    fi
    if [[ ! -d "$templateloc" ]]; then
        pause_and_exit_with_error "Project Template '$projtemplate' not found."
    fi

    showBanner "$BANNER_LABEL development Eclipse Project Setup"

    show_eclipse_rt_version_string
    echo
    
    test_for_compatible_rt_version_during_setup
    test_for_downgrade_during_setup
    echo "Enter info for your project, or at any time you may" \
         "hit $PLATFORM_BREAK_KEY to quit."
    echo
    
    setup_common_on_entry

    if [[ "$commonsuccess" != "true" ]]; then
        exit
    fi

    updateProgress "Instantiating project from template..."

    mkdir -p "$PROJECT_PATH"; updateProgress

    pushd "$templateloc" >& /dev/null

    if [[ -e ./._cproject ]]; then
        cp ./._cproject "$PROJECT_PATH/.cproject"; updateProgress
    fi
    if [[ -e ./._project ]]; then
        cp ./._project "$PROJECT_PATH/.project"; updateProgress
    fi

    local rmrfstatus=1
    while [[ $rmrfstatus != 0 ]]; do
        rm -rf "$PROJECT_PATH/.settings"
        rmrfstatus=$?
        if [[ $rmrfstatus != 0 ]]  || [[ -d "$PROJECT_PATH/.settings" ]]; then
            echo
            show_error "Deleting of .settings failed, folder probably in use" \
                 "by another program. Hit $PLATFORM_BREAK_KEY to quit or" \
                 "close the program or window accessing the $PROJECT_NAME" \
                 "folder and press enter to continue."
            pause
        fi
    done

    # This is a brand new project, there was no backup
    if [[ ! -d "$PROJECT_PATH.bak" ]]; then
        # So let's populate this folder with the non-dot files
        # This will include settings folder, so...
        cp -Rf ./* "$PROJECT_PATH/."; updateProgress
        # Move the settings folder to be the proper .folder name
        mv "$PROJECT_PATH/settings" "$PROJECT_PATH/.settings"
    else
        # This is just a refresh of an existng project (b/c there was a backup)
        # So all we need is the settings folder.
        cp -Rf ./settings "$PROJECT_PATH/.settings"; updateProgress
    fi

    popd >& /dev/null

    pushd "$PROJECT_PATH" >& /dev/null; updateProgress

    # Are we instantiating a brand new project from a template, thus we are
    # adding source files?
    if [[ ! -d "$PROJECT_PATH.bak" ]]; then

        if [[ -e docs._doxyfile ]]; then
            mv docs._doxyfile docs.doxyfile
        fi

        updateProgress

        if [[ -d CVSDIR ]]; then
            find . -name CVSDIR | \
                sed "s#\(.*\)/CVSDIR#mv \1/CVSDIR \1/CVS#" | sh

            updateProgress

            local rootlist="$(find . -name "Root" | grep "CVS/Root")"

            if [[ -n "$rootlist" ]]; then
                sedInPlace "s/cvsusr/$cvsusr/g" $rootlist
            fi
        fi
    fi

    # Construct a new project list, adding in remote_eclipse and
    # remote_headers.
    projectList="$prevProjectList"

    projectList="remote_eclipse:$projectList"
    projectList="remote_headers:$projectList"
    projectList="${projectList%:}"
    
    # Now sort the list of projects alphabetically, the natural order
    # within Eclipse itself.
    projectList="$(echo "$projectList" | \
        tr ':' '\n' | sort -u | tr '\n' ':')"
    projectList="${projectList%:}"

    local repl="${projectList//:/</project>_~_${_TAB}${_TAB}<project>}"

    sedInPlace "s/$projtemplate/$PROJECT_NAME/g" .project .cproject
    sedInPlace "s#${_TAB}${_TAB}<project></project>#${_TAB}${_TAB}<project>$repl</project>#g" .project
    sedInPlace 's/_~_/\'$'\n/g' .project

    setup_project_ignore_files
    setup_common_variables
    updateProgress "Setting variables and targets..."
    add_universal_targets
    setup_${PROJECT_CODE}_variables_and_targets
    write_targets_to_project
    replace_build_command "$mainsubproj"
    replace_config_names
    replace_c_flags_and_cxx_flags
    replace_config_source_exclusion_filter
    add_refresh_scope_entry -resourceType "FOLDER" -workspacePath "${lochdrcache}"

    # We only define the variable binpath if we are not running
    # Windows AND the path to remote_eclipse itself has a space in it,
    # because Eclipse has a bug where it cannot use an explicit path
    # with spaces as the location of the GDB target, and that thus the
    # workaround is to put that location in the PATH itself, which is
    # what is being done here.
    if   [[ "${REMOTE_ECLIPSE_LOC}" != "${REMOTE_ECLIPSE_LOC/ /}" ]] && \
         [[ "${WORKSPACE_LOC:0:1}" == "/" ]]; then
        local LOCDS="/" # Local directory separator
        local LOCPD=":" # Local Path delimiter
        local binpath="${REMOTE_ECLIPSE_LOC}"
        binpath="${binpath}${LOCDS}local_os${LOCDS}${ECLIPSE_SYSTEM_OS}${LOCPD}"
    fi
    
    updateProgress "Saving variables and settings..."

    saveVariablesToProject -allConfigs -from buildusr      REMOTEBUILDUSER \
                                       -from buildhst      REMOTEBUILDHOST \
                                       -from builddir      REMOTEPROJECTDIR \
                                       -from deployusr     REMOTEDEPLOYUSER \
                                       -from deployhst     REMOTEDEPLOYHOST \
                                       -from debugbuild    ENABLEDEBUGBUILD \
                                       -from prevcorefile  COREFILE \
                                       -from prevbuildopts CUSTOM_BUILD_OPTS \
                                       -from binpath       PATH \
                                       -from lochdrcache   LOCALHDRCACHE \
                                       -from remotehp      REMOTEHDRPATHS


    # Only instantiate the source files if we are making the project for the
    # first time.
    if [[ -n "$sourceFiles" ]] && [[ ! -d "$PROJECT_PATH.bak" ]]; then
        local sedexp=""
        sedexp="${sedexp};s/YYYY/$(date +%Y)/g"
        sedexp="${sedexp};s/cvsusr/$cvsusr/g"
        sedexp="${sedexp};s/$projtemplate/$PROJECT_NAME/g"
        if [[ -n "$thebinary" ]]; then
            sedexp="${sedexp};s/thebinary/$thebinary/g"
        fi
        if [[ -n "$tmplmainsrcfile" ]]; then
            sedexp="${sedexp};s/$tmplmainsrcfile/$mainsrcfile/g"
        fi
        if [[ -n "$tmplcppext" ]]; then
            sedexp="${sedexp};s/\.$tmplcppext/.$cppext/g"
        fi
        if [[ -n "$tmplhppext" ]]; then
            sedexp="${sedexp};s/\.$tmplhppext/.$hppext/g"
        fi
        if [[ -n "$tmplmainsubproj" ]]; then
            if [[ "$mainsubproj" == "." ]]; then
                sedexp="${sedexp};s/${tmplmainsubproj}\\([_\\.]\\)/${projname}\\1/g"
                sedexp="${sedexp};s/-targetPath ${tmplmainsubproj} //g"
            fi
            sedexp="${sedexp};s/$tmplmainsubproj/$mainsubproj/g"
        fi
        sedexp="${sedexp:1}"
        sedInPlace "$sedexp" $sourceFiles
    fi

    if [[ -n "$tmplmainsubproj" ]]; then
        if [[ ! -d "$PROJECT_PATH.bak" ]]; then
            if [[ "$mainsubproj" == "." ]]; then
                pushd "$tmplmainsubproj" >& /dev/null
                mv * ..
                popd >& /dev/null
                rmdir "$tmplmainsubproj"
            else
                mv "$tmplmainsubproj" "$mainsubproj"
            fi
            if [[ -n "$tmplmainsrcfile" ]]; then
                mv "$mainsubproj/$tmplmainsrcfile" "$mainsubproj/$mainsrcfile"
            fi
        fi
    fi

    local csed=""
    csed="$csed;s#all_version_specific_headers#${allVersionSpecificHeaders// /,}#"
    csed="$csed;s#tabulationChar#${tabulationChar:-space}#"
    csed="${csed#;}"
    sedInPlace "${csed}" .settings/org.eclipse.cdt.core.prefs

    unix2platform ".settings/org.eclipse.cdt.core.prefs" >& /dev/null

    if [[ -e ".settings/language.settings.xml" ]]; then
        sedInPlace "s#perResourceScope#$perResourceScope#" \
            .settings/language.settings.xml

        unix2platform ".settings/language.settings.xml" >& /dev/null
    fi

    if [[ -d "$PROJECT_PATH.bak" ]]; then
        removeLegacyDotFilesFromProject
    fi

    popd >& /dev/null

    return
}

wait_for_project_to_close()
{
    local actionLabel=setup
    while [[ "${1#-}" != "${1}" ]]; do
        case $1 in
            -action)
                shift
                actionLabel="$1"
                ;;
        esac
        shift
    done
    
    echo "The Eclipse project '$PROJECT_NAME' is still open."
    echo
    echo "To finish $actionLabel:"
    echo
    echo "1. Select the '$PROJECT_NAME' project in Project Explorer."
    echo "2. Select Project > Close Project (or right-click and Close Project)."
    echo "3. Once the project is closed, this window will automatically close."
    echo "4. After this window closes, you may re-open the project."
    echo
    echo "   NOTE: Ignore any 'Serialize CDT language settings entries' error messages"
    echo "         if they occur.  They are harmless and expected."

    local i=0
    
    while isProjectOpen; do
        if [[ $i == 0 ]]; then
            updateProgress "Waiting for the user to close the project..."
        fi
        sleep 3
        
        if [[ $i -lt 20 ]]; then
            let i=$i+1
            # Show an updating ... progress indicator, up until 20 then stop
            # incrementing the indicator (but still keep waiting...)
            updateProgress
        fi
    done
    
    echo
    echo

    # OK to proceed
    return
}

warn_that_already_exists()
{
    echo
    echo "Project name: $PROJECT_NAME already exists!"
    echo
    echo "Location: $PROJECT_LOC"
    echo

    local theprompt="**RE-CREATE** settings (files will be kept)"
    theprompt="$theprompt for $PROJECT_NAME? [yes]: "
    read -p "$theprompt" yes_or_no

    if [[ "${yes_or_no:0:1}" == "n" ]] || [[ "${yes_or_no:0:1}" == "N" ]]; then
        exit
    fi

    # OK to proceed
    return
}

ask_debug_configuration()
{
    # If we are passed this configuation setting, don't bother to ask.
    if is_debug_release_project; then
        unset debugbuild
        return
    elif [[ -n "$ENABLEDEBUGBUILD" ]]; then
        debugbuild="$ENABLEDEBUGBUILD"
        return
    fi

    local options="false|true"
    echo
    echo "false    - Release build, full optimizations, for production packages"
    echo "true     - Debug build, no optimizations (best for use with gdb)"
    if [[ "$HAS_MEMDEBUG" == "true" ]]; then
        echo "memdebug - Debug build + memory-leak detection"
        options="$options|memdebug"
    else
        # If you don't allow memdebug and that's the default, downgrade to true
        if [[ "$prevdebugbuild" == "memdebug" ]]; then
            prevdebugbuild=true
        fi
    fi

    local theprompt
    theprompt="Debug Build? <$options> [$prevdebugbuild]: "
    debugbuild=
    while  [[ -z "$debugbulid" ]]; do
        echo
        read -p "$theprompt" debugbuild
        if [[ -z "$debugbuild" ]]; then
            debugbuild=$prevdebugbuild
        fi

        case $debugbuild in
            true|false)
                break
                ;;
            memdebug)
                if [[ "$HAS_MEMDEBUG" == "true" ]]; then
                    break
                fi
                ;;
        esac
        show_error "Invalid selection $debugbuild."
        debugbuild=
    done
}

read_previous_configuration()
{
    pushd "$PROJECT_PATH" >& /dev/null

    # Now get all the variables from the existing project, but store them
    # under a different variable name with prev in the name.
    getVariableFromProject -to prevbuildhst REMOTEBUILDHOST "$prevbuildhst"

    prevbuilddir=
    getVariableFromProject -to prevbuilddir REMOTEPROJECTDIR "$prevbuilddir"

        if [[ -n "$prevbuilddir" ]]; then
        # For new projects, separate the build dir into the old-style
        # project vs. home breakdown.
        prevbuildhme="${prevbuilddir%/*}"
        prevremoteprojname="${prevbuilddir##*/}"
    else
        # For old projects, the project name vs. home is already broken down
        getVariableFromProject -to prevbuildhme REMOTEBUILDHOME "$prevbuildhme"
        getVariableFromProject -to prevremoteprojname REMOTEPROJECTNAME "$prevremoteprojname"
    fi

    getVariableFromProject -to prevbuildusr REMOTEBUILDUSER "$prevbuildusr"
    getVariableFromProject -to prevdeployhst REMOTEDEPLOYHOST "$prevdeployhst"
    getVariableFromProject -to prevdeployusr REMOTEDEPLOYUSER "$prevdeployusr"
    getVariableFromProject -to prevdebugbuild ENABLEDEBUGBUILD "$prevdebugbuild"
    getVariableFromProject -to prevcorefile COREFILE "$prevcorefile"
    getVariableFromProject -to prevbuildopts CUSTOM_BUILD_OPTS "$prevbuildopts"
    getVariableFromProject -to prevmainsubproj MAINSUBPROJ "$prevmainsubproj"
    getVariableFromProject -to prevlocalhdrcache LOCALHDRCACHE "$prevlocalhdrcache"
    getVariableFromProject -to prevremotehp REMOTEHDRPATHS "$prevremotehp"
    remove_path_variable_legacy_escaping

    # If we are dealing with re-creating an old generic project where we
    # don't have the project variable (which we no longer save)
    # let's instead go and grab it from the default build path.
    if [[ -z "$prevmainsubproj" ]]; then
        local sedexp="s#.*buildPath=\\\"\\\${workspace_loc:\\(.*\\)}\\\""
        sedexp="${sedexp} cleanBuildTarget=.*#\\1#p"
        prevBuildPath="$(sed -n -e "${sedexp}" .cproject | head -n 1)"
        # Tack on an extra slash, then remove the first /project/ part.  This
        # way, if there is no sub-project, we end up with a null
        prevmainsubproj="${prevBuildPath}/"
        prevmainsubproj="${prevBuildPath#/*/}"
        # Now remove that final /
        prevmainsubproj="${prevmainsubproj%/}"
        if [[ -z "$prevmainsubproj" ]]; then
            prevmainsubproj="."
        fi
    fi

    prevProjectList=$(cat .project | \
        sed -n "s#.*<project>\\(.*\\)</project>#\\1#p" | \
        grep -v "remote_eclipse" | \
        grep -v "remote_headers" | \
        tr '\n' ':')
    prevProjectList="${prevProjectList%:}"

    popd >& /dev/null
}

update_header_cache_from_setup()
{
    local REMOTEBUILDUSER="$buildusr"
    local REMOTEBUILDHOST="$buildhst"
    local REMOTEHDRPATHS="$remotehp"
    local LOCALHDRCACHE="$lochdrcache"
    update_header_cache
}

setup_common_on_entry()
{
    commonsuccess=false

    # ==========================================
    # Get previous values for host and usernames
    # ==========================================

    cd "$WORKSPACE_PATH"

    USER_PREFS_FOLDER="${REMOTE_ECLIPSE_PATH%/*}/user_preferences"

    import_legacy_user_preferences

    getVariableFromFile prevcvsusr    "$USER_PREFS_FOLDER/cvsusr"
    getVariableFromFile prevbuildhst  "$USER_PREFS_FOLDER/buildhst"
    getVariableFromFile lastbuildhme  "$USER_PREFS_FOLDER/buildhme"
    getVariableFromFile prevbuildusr  "$USER_PREFS_FOLDER/buildusr"
    getVariableFromFile prevdeployusr "$USER_PREFS_FOLDER/deployusr"
    getVariableFromFile prevdeployhst "$USER_PREFS_FOLDER/deployhst"
    getVariableFromFile prevdebugbuild "$USER_PREFS_FOLDER/debugbuild"

    if [[ -z "$PROJECT_NAME" ]]; then
        read -p "Project name [$defprojname]: " projname
        if [[ -z "$projname" ]]; then
            projname="$defprojname"
        fi

        # This will allow us to pull settings out of the pre-existing project.
        export PROJECT_NAME=$projname

        #Used by the removeLegacyDotFilesForVariables script (below)
        export PROJECT_LOC
        getProjectLocation PROJECT_LOC "$PROJECT_NAME"
    fi

    if [[ -n "$PROJECT_LOC" ]] ; then
        # We found the project location.
        if [[ ! -e "$PROJECT_LOC" ]]; then
            show_error "Cannot find project location."
            pause
            exit
        fi
        PROJECT_PATH="$(cd "$PROJECT_LOC" && pwd)"
    else
        if [[ "${WORKSPACE_LOC:0:1}" == "/" ]]; then
            PROJECT_LOC="$WORKSPACE_LOC/$PROJECT_NAME"
        else
            PROJECT_LOC="$WORKSPACE_LOC\\$PROJECT_NAME"
        fi
        PROJECT_PATH="$WORKSPACE_PATH/$PROJECT_NAME"
    fi

    export LOCALPROJECTDIR="$PROJECT_PATH"

    prevremoteprojname="$PROJECT_NAME"

    reusingproject=false
    
    if hasConfigurationProvider; then
        if isInSourceSetupProject; then
            # This is a setup via a setup make target, so they know
            # the project exists so we do nothing.
            :
        else
            # This is a project set up via the external tool "Setup a Remote Project"
            # Thus we need to warn that the project exists, in case they unknowingly 
            # typed the name of an existing project.
            warn_that_already_exists
            echo
        fi

        reusingproject=true
        read_previous_configuration
    fi

    # Make sure all projects have CUSTOMBUILDOPTS and COREFILE variables
    # in the project even if blank.
    prevcorefile="${prevcorefile}"
    prevbuildopts="${prevbuildopts}"

    if [[ -z "$prevdeployhst" ]]; then
        prevdeployhst=none
    fi

    if [[ -z "$prevdeployusr" ]]; then
        prevdeployusr=root
    fi

    if [[ -z "$prevdebugbuild" ]]; then
        prevdebugbuild=memdebug
    fi
    
    if [[ -z "$prevbuildhst" ]]; then
        while [[ -z "$buildhst" ]]; do
            read -p "Remote build system: " buildhst
        done
    else
        read -p "Remote build system [$prevbuildhst]: " buildhst
        if [[ -z "$buildhst" ]]; then
            buildhst=$prevbuildhst
        fi
    fi

    # If there was a build user for a particular machine, prefer it since it's
    # going to a better default for that box.
    if     [[ "$reusingproject" == "false"   ]] || \
           [[ "$buildhst" != "$prevbuildhst" ]]; then
        getVariableFromFile lastbuildusr \
            "$USER_PREFS_FOLDER/buildusr.$buildhst" "$lastbuildusr"

        if [[ -n "$lastbuildusr" ]]; then
            prevbuildusr=$lastbuildusr
        fi
    fi

    if [[ -z "$prevbuildusr" ]]; then
        buildusrprompt=
    else
        buildusrprompt=" [$prevbuildusr]"
    fi

    read -p "Username on remote build system${buildusrprompt}: " buildusr
    if [[ -z "$buildusr" ]]; then
        buildusr=$prevbuildusr
    fi

    cvsusr=
    if [[ "$usescvs" == "true" ]]; then
        if [[ -z "$prevcvsusr" ]]; then
            prevcvsusr=$buildusr
        fi
        if [[ -z "$prevcvsusr" ]]; then
            cvsusrprompt=
        else
            cvsusrprompt=" [$prevcvsusr]"
        fi

        while [[ -z "$cvsusr" ]]; do
            read -p "Username on revision control system${cvsusrprompt}: " cvsusr
            if [[ -z "$cvsusr" ]]; then
                cvsusr=$prevcvsusr
            fi
        done
    else
        if [[ -n "$prevcvsusr" ]]; then
            cvsusr=$prevcvsusr
        else
            cvsusr=$buildusr
        fi
    fi

    # If there was a build home for a particular machine, prefer it since it's
    # going to be consistent with the naming structure for that box.
    getVariableFromFile lastbuildhme \
        "$USER_PREFS_FOLDER/buildhme.$buildhst" "$lastbuildhme"

    # Get the user before trying to fill in the previous build home
    # (default) value, since if there is no previous answer, we need
    # the currently chosen build user to fill it in.
    if     [[ "$reusingproject" == "true"    ]] && \
           [[ "$buildhst" == "$prevbuildhst" ]]; then
        if [[ -z "$prevbuildhme" ]]; then
            if [[ -z "$lastbuildhme" ]]; then
                prevbuildhme=/home/$buildusr
            else
                prevbuildhme=$lastbuildhme
            fi
        fi
    else
        if [[ -z "$prevbuildhme" ]] || [[ "$buildhst" != "$prevbuildhst" ]]; then
            if [[ -z "$lastbuildhme" ]]; then
                prevbuildhme=/home/$buildusr
            else
                prevbuildhme=$lastbuildhme
            fi
        fi
    fi

    prevbuilddir=$prevbuildhme/$prevremoteprojname

    read -p "Remote mapped project path [$prevbuilddir]:" builddir
    if [[ -z "$builddir" ]]; then
        builddir="$prevbuilddir"
    fi

    # Strip off any trailing /
    builddir=${builddir%/}

    buildhme="${builddir%/*}"
    remoteprojname="${builddir##*/}"

    mainsubproj=
    if [[ -n "$defmainsubproj" ]]; then
        if [[ -n "$prevmainsubproj" ]]; then
            # We are updating an existing project, so you can't ask about
            # the mainsubproj, and the main source file can't change either.
            mainsubproj=$prevmainsubproj
            tmplmainsrcfile=
        else
            read -p "Build subfolder (. recommended) [$defmainsubproj]: " mainsubproj
            if [[ -z "$mainsubproj" ]]; then
                mainsubproj=$defmainsubproj
            fi
            #Use the module name in lowercase as the binary name
            local ModuleCamelCase=
            snake_to_camel_case ModuleCamelCase "$mainsubproj"
            if [[ "$mainsubproj" == "." ]]; then
                snake_to_camel_case ModuleCamelCase "$projname"
            else
                snake_to_camel_case ModuleCamelCase "$mainsubproj"
            fi
            defthebinary="$ModuleCamelCase"
            thebinary=
            read -p "Binary name [$defthebinary]: " thebinary
            if [[ -z "$thebinary" ]]; then
                thebinary=$defthebinary
            fi
        fi
    fi

    mainsrcfile=
    cppext=
    hppext=
    if [[ -n "$tmplmainsrcfile" ]]; then
        defmainsrcfile=${thebinary}.cpp
        local isvalidcppext=false
        while  [[ -z "$mainsrcfile" ]] || \
               [[ "${isvalidcppext}" != "true" ]]; do
            mainsrcfile=
            read -p "Main source file [$defmainsrcfile]: " mainsrcfile
            if [[ -z "$mainsrcfile" ]]; then
                mainsrcfile=$defmainsrcfile
            fi
            cppext="${mainsrcfile##*.}"
            if  [[ "${cppext}" == "cpp" ]] || \
                [[ "${cppext}" == "cxx" ]] || \
                [[ "${cppext}" == "cc"  ]]; then

                isvalidcppext=true
            fi
        done
        if [[ "${cppext}" == "cc" ]]; then
            hppext="hh"
        elif [[ "${cppext}" == "cpp" ]]; then
            hppext="hpp"
        elif [[ "${cppext}" == "cxx" ]]; then
            hppext="hxx"
        fi
    fi

    if [[ -n "$REMOTEDEPLOYHOST" ]]; then
        deployhst="$REMOTEDEPLOYHOST"
    else
        read -p "Deployment system (or type none) [$prevdeployhst]: " deployhst
        if [[ -z "$deployhst" ]]; then
            deployhst=$prevdeployhst
        fi
    fi

    if [[ "${deployhst}" == "none" ]]; then
        deployusr=root
    else
        read -p "Username on deployment system [$prevdeployusr]: " deployusr
        if [[ -z "$deployusr" ]]; then
            deployusr=$prevdeployusr
        fi
    fi

    ask_debug_configuration

    # sniemczyk: 2014-11-23: Let's assume we will prompt the user to change
    # the platform label, etc. but if we are refreshing a project and a prior
    # platform was detected, we can offer to skip the prompts if everything
    # is the same.  Also, we can pass an environment variable to suppress
    # prompting.
    promptToChangePlatform=${PROMPT_TO_CHANGE_PLATFORM:-silent-update}
    get_prompt_to_change_platform

    # sniemczyk: 2014-11-23: If all we are doing is updating a project,
    # pausing at the end is not necessary since we can just let the project
    # refresh.  Of course, if we want to see any errors, pausing at the end
    # could be desireable.
    pauseAtEndOnUpdate=${PAUSE_AT_END_ON_UPDATE:-true}
    get_prompt_to_pause_on_finished_update

    # Make sure HEADER_LOCATIONS and DEBUG_SOURCE_LOCATIONS have
    # no legacy escaping
    verify_no_legacy_escaped_path_variables

    # Look to see if HEADER_LOCATIONS are defined, and if so use it.
    HEADER_LOCATIONS="${HEADER_LOCATIONS-/usr/local/include}"
    # Look to see if DEBUG_SOURCE_LOCATIONS are defined, and if so use it.
    export DEBUG_SOURCE_LOCATIONS="${DEBUG_SOURCE_LOCATIONS-/usr/src/debug}"
    

    export INDEXER_CXX_COMPILER="${INDEXER_CXX_COMPILER:-g++}"
    export INDEXER_C_COMPILER="${INDEXER_C_COMPILER:-gcc}"

    # HEADER_LOCATIONS and DEBUG_SOURCE_LOCATIONS hints, plus
    # INDEXER_CXX_COMPILER above are used during key-setup
    source key-setup.sh
    status=$?
    if [[ "$status" != "0" ]]; then
        exit $status
    fi

    headercacheprj=remote_headers
    get_remote_platform
    getHeaderCacheLocation
    updateHeaderCache=true

    if ! hasHeaderCache; then
        mkdir -p "${REMOTE_ECLIPSE_PATH%/*}/$hdrcachepath"
    else
        # Is there was previous header path, and do we see no change? it is
        # probably safe to not update the header cache, but we can ask the
        # question if requested.
        if [[ -n "$prevremotehp" ]] && [[ "$prevremotehp" == "$remotehp" ]]; then
            if [[ "$promptToChangePlatform" == "silent-update" ]]; then
                updateHeaderCache=true
                promptToChangePlatform=false
            elif [[ "$promptToChangePlatform" == "true" ]]; then
                echo
                local yes_or_no=
                local theprompt="Update ${remote_platform} cache? [yes]: "
                read -p "$theprompt" yes_or_no

                if  [[ "${yes_or_no:0:1}" != "n" ]] && \
                    [[ "${yes_or_no:0:1}" != "N" ]]; then
                    updateHeaderCache=true
                else
                    updateHeaderCache=false
                fi
            else
                updateHeaderCache=false
            fi
        else
            updateHeaderCache=true
            if [[ "$promptToChangePlatform" == "true" ]]; then
                if [[ -n "$prevremotehp" ]]; then
                    # There was a previous value for the list of header folders, and
                    # it is now different.  Switch default action to update, and always
                    # show the prompt.
                    echo
                    echo "Change detected in headers on ${remote_platform}!"
                    echo
                    local yes_or_no=
                    local theprompt="Update ${remote_platform} cache? [yes]: "
                    read -p "$theprompt" yes_or_no

                    if  [[ "${yes_or_no:0:1}" != "n" ]] && \
                        [[ "${yes_or_no:0:1}" != "N" ]]; then
                        updateHeaderCache=true
                    else
                        updateHeaderCache=false
                    fi
                else
                    # There was no previous value, yet offer to update anyway
                    echo
                    local yes_or_no=
                    local theprompt="Update ${remote_platform} cache? [yes]: "
                    read -p "$theprompt" yes_or_no

                    if  [[ "${yes_or_no:0:1}" != "n" ]] && \
                        [[ "${yes_or_no:0:1}" != "N" ]]; then
                        updateHeaderCache=true
                    else
                        updateHeaderCache=false
                    fi
                fi
            fi
        fi
    fi

    # Adding logic to check if all the folders expected in our cache are
    # present.  If not, we should pay the price of doing an inbound sync.
    if [[ "$updateHeaderCache" == "false" ]]; then
        IFS=":"
        for headerFolder in $remoteih; do
            local fullheaderCachePath="${REMOTE_ECLIPSE_PATH%/*}/$hdrcachepath"
            if [[ ! -d "$fullheaderCachePath/$headerFolder" ]]; then
                echo
                echo "Missing $headerFolder in cache, forcing remote sync."
                updateHeaderCache=true
                break
            fi
        done
        unset IFS
    fi

    if [[ "$updateHeaderCache" == "true" ]]; then
        update_header_cache_from_setup
    fi

    if [[ -n "$cvsusr" ]]; then
        saveVariableToFile cvsusr "$USER_PREFS_FOLDER/cvsusr"
    fi
    saveVariableToFile buildusr "$USER_PREFS_FOLDER/buildusr"
    saveVariableToFile buildhst "$USER_PREFS_FOLDER/buildhst"
    saveVariableToFile buildhme "$USER_PREFS_FOLDER/buildhme"
    if [[ -n "$buildhst" ]]; then
        saveVariableToFile buildhme "$USER_PREFS_FOLDER/buildhme.$buildhst"
        saveVariableToFile buildusr "$USER_PREFS_FOLDER/buildusr.$buildhst"
    fi
    saveVariableToFile deployusr "$USER_PREFS_FOLDER/deployusr"
    saveVariableToFile deployhst "$USER_PREFS_FOLDER/deployhst"
    saveVariableToFile debugbuild "$USER_PREFS_FOLDER/debugbuild"

    if [[ -d "$PROJECT_PATH" ]] && [[ -e "$PROJECT_PATH/.cproject" ]]; then
        if [[ -d "$PROJECT_PATH.bak" ]]; then
            rm -rf "$PROJECT_PATH.bak"
        fi
        # Make a backup of the settings we plan to change.
        # if we fail, the exit handler will copy these back.
        mkdir -p "$PROJECT_PATH.bak"
        pushd "$PROJECT_PATH" >& /dev/null
        if [[ -e .cproject ]]; then
            cp .cproject "$PROJECT_PATH.bak"
        fi
        if [[ -e .project ]]; then
            cp .project "$PROJECT_PATH.bak"
        fi
        if [[ -d .settings ]]; then
            cp -Rf .settings "$PROJECT_PATH.bak"
        fi
        popd >& /dev/null
    fi

    commonsuccess=true

    return
}

setup_common_on_exit()
{
    action=created

    if [[ -e "$PROJECT_PATH.bak" ]]; then
        rm -rf "$PROJECT_PATH.bak"
        action=updated
    fi

    echo
    echo
    echo
    echo
    echo
    showBanner "Project $PROJECT_NAME was $action."

    # Now, if the project is in source, we need to 
    if isInSourceSetupProject; then
        if isProjectOpen; then
            wait_for_project_to_close -action setup
        fi
    elif [[ "$action" == "updated" ]]; then
        show_updated_project_import_instructions
    else
        show_new_project_import_instructions
    fi
    
    if  [[ "$action"                 != "updated" ]] || \
        [[ "$pauseAtEndOnUpdate"     ==    "true" ]]; then
        echo
        pause
    else
        echo
        if isInSourceSetupProject; then
            echo "Closing now..."
        else
            echo "Closing in 3 seconds..."
            sleep 3
        fi
    fi
    return
}

show_new_project_import_instructions()
{
    echo "Use Eclipse's import capability to bring in this new project:"
    echo
    echo "1. Select File/Import from Eclipse's menu."
    echo "2. Select General/Existing Projects Into Workspace, click Next."
    echo "3. Click \"Browse\" and navigate to the folder:"
    echo "   \"$PROJECT_LOC\""
    echo "4. Click OK, then Finish."
    echo "5. Right click on $PROJECT_NAME in the Project Explorer"
    echo "   and select Close Project."
    echo "6. Right click on it again and re-open the project" \
            "(select Open Project)"
    if [[ -d "$PROJECT_PATH/CVS" ]]; then
        echo "7. Right click on $PROJECT_NAME again, and select"
        echo "   Replace With > Latest from HEAD."
        echo "8. Optionally, you may then switch to a different" \
                "branch tag or version:"
        echo "9. Right click project or folder(s), Team=>Switch" \
                "to Another Branch or Version."
    fi
}

show_updated_project_import_instructions()
{
    echo "Be sure to close this window: once you do, Eclipse will"
    echo "automatically refresh the $PROJECT_NAME project so"
    echo "that the changes will take effect."
    echo
    echo "NOTE: if the project is currently closed, you will need to"
    echo "      right click on it after opening and click Refresh."
}

test_for_eclipse()
{
    if [[ ! -d "$WORKSPACE_PATH/.metadata/.plugins" ]]; then
        show_error "Not launched from within the Eclipse" \
             "environment.  Exiting."
        pause
        exit 255
    fi
}

test_for_git()
{
    # Try to run git --version and look for the "git version" string
    local gitVersionLine="$(git --version 2> /dev/null)"
    if [[ "$gitVersionLine" == "${gitVersionLine/git version/}" ]]; then
        show_error "Cannot find git in the path.  Please" \
             "fix and restart Eclipse.  Exiting."
        pause
        exit 255
    fi
}

test_for_compatible_rt_version_during_setup()
{
    if ! is_current_eclipse_rt_version_compatible; then
        local minVer=$(get_minimum_eclipse_rt_version)
        echo "***ERROR:*** The current version of Eclipse for Remote Targets is NOT"
        echo "compatible with this project."
        echo
        show_error "The minimum version required by this project is $minVer."
        echo
        echo "Please update your Eclipse for Remote Targets and try to setup again."
        echo
        pause
        exit 255
    fi
}

test_for_downgrade_during_setup()
{
    if is_eclipse_rt_version_setup_downgrade; then
        echo "***WARNING:*** This project was set up with a newer version of"
        echo "Eclipse for Remote Targets (version ${ECLIPSE_RT_VERSION_AT_SETUP})."
        echo
        echo "It may not be possible to downgrade successfully, possibly requiring"
        echo "re-downloading the source from scratch.  Proceed with caution."
        echo
    fi
}

wait_for_unsetup_close()
{
    echo "Reverting project to the original state..." \
         "(press $PLATFORM_BREAK_KEY to cancel.)"
    echo
    echo "Remote folder is: $REMOTEPROJECTDIR"
    echo
    local yes_or_no=
    local theprompt="Wipe remote project folder? [yes]: "
    read -p "$theprompt" yes_or_no

    if    [[ "${yes_or_no:0:1}" != "n" ]] && \
          [[ "${yes_or_no:0:1}" != "N" ]]; then
        echo
        trace_on
        ssh "$REMOTEBUILDUSER@$REMOTEBUILDHOST" rm -rf "$REMOTEPROJECTDIR"
        trace_off
    else
        echo
    fi
    echo
    unsetup_project_ignore_files
    wait_for_project_to_close -action unsetup
}

setup_project_main()
{
    verify_no_legacy_escaped_path_variables
    if [[ "$1" == "-unsetup" ]]; then
        wait_for_unsetup_close
        return
    fi
    
    test_for_eclipse && \
    test_for_git && \
    choose_project_type && \
    clear && \
    setup_${PROJECT_CODE}_project && \
    setup_project_generic && \
    setup_common_on_exit
}

setup_project_main "$@"