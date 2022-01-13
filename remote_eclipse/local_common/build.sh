#! /bin/bash
#
# build.sh -- Main Eclipse build command
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License 
# accompanying the software (“License”).  This software is distributed “AS IS” 
# as set forth in the License.


# Header files
source remote-dev-config.sh

isBuildActionGetCompilerSpecs()
{
    # Return true if our build-action starts with get-compiler specs.
    # Note that we replace the build action with the full argument list
    # which is why we have to check using the prefix technique here as
    # opposed to a literal match.
    [[ "${buildaction#get-compiler-specs}" != "${buildaction}" ]]
}

set_indexer_preferences()
{
    if [[ -z "$INDEXER_CXX_COMPILER" ]]; then
        INDEXER_CXX_COMPILER="g++"
    fi
    if [[ -z "$INDEXER_C_COMPILER" ]]; then
        INDEXER_C_COMPILER="gcc"
    fi
    if [[ -z "$INDEXER_CXX_FLAGS" ]]; then
        INDEXER_CXX_FLAGS="${CXXFLAGS}"
    fi
    if [[ -z "$INDEXER_C_FLAGS" ]]; then
        INDEXER_C_FLAGS="${CFLAGS}"
    fi
}

set_build_preferences()
{
    rsyncdefaultverbosity=-q
    #     ^^^^^^^^^^^    =-q
    rsyncdopull=true
    rsyncdopush=true
    outgoingrsyncopts="-avz --perms --no-o --no-g"
    incomingrsyncopts="-rtvz --perms --no-o --no-g"
    srcbindir="$REMOTE_ECLIPSE_PATH/remote_unix"
    rsyncconfigdir="$REMOTE_ECLIPSE_PATH/rsync_config"
}

read_rsync_entry()
{
    if [[ -z "$1" ]]; then
        exit_with_error "$FUNCNAME: Must supply function to read."
    fi

    local line=
    local leadingSpace=""
    "$@" | \
    while read line; do
        local file
        local prefix
        # Trimming any leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ -z "${line}" ]]; then
            continue
        elif [[ "${line:0:2}" == "+ " ]]; then
            file="${line:2}"
            prefix="--include"
        else
            file=$line
            prefix="--exclude"
        fi
        echo -n "${leadingSpace}$prefix='$file'"
        leadingSpace=" "
    done
    # Get the result of the command, since it may be ACTION_NOT_IMPLEMENTED
    local exitStatus="${PIPESTATUS[0]}"
    echo
    return $exitStatus
}

getRsyncSubProjectExclusionRule()
{
    local varname=$1
    shift

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    local ruleOption=-get-rsync-exclusion-rule

    if [[ "$1" == "-inbound" ]]; then
        ruleOption=-get-rsync-inbound-exclusion-rule
    fi

    local multiActionScript=
    find_multi_action_script multiActionScript $subprojname

    local _rule=""
    # Try first to find a rule via the multi-action script
    if [[ -e "$multiActionScript" ]]; then
        _rule="$(read_rsync_entry source "$multiActionScript" $ruleOption)"
        if [[ "$?" == "$ACTION_NOT_IMPLEMENTED" ]]; then
            _rule="" # Do nothing and fall through to normal search method
        elif [[ -z "${_rule}" ]]; then
            # If the rule is intentionally blank (sync all) make it a single space)
            _rule=" "
        else
            : # We have a rule, let's use that one
        fi
    fi

    # If not, let's try to find an exclusion file in the sub-project
    if [[ "$1" != "-inbound" ]] && [[ -z "${_rule}" ]]; then
        local override_names="remote_eclipse_rsync_exclude.txt rsync-exclude"
        local rsyncsubprojexclfile

        for override_name in $override_names; do
            rsyncsubprojexclfile="$LOCALPROJECTDIR/$subprojname/$override_name"
            if [[ -e "$rsyncsubprojexclfile" ]]; then
                _rule="--exclude-from='$rsyncsubprojexclfile'"
                break
            fi
        done
    fi

    eval "$varname=\"${_rule}\""
}

get_symbol_list()
{
    set_indexer_preferences

    # Strip off any leading -, and get the first letter
    opt="${1#-}"
    opt="${opt:0:1}"

    local symbol_list=
    local flags="$INDEXER_CXX_FLAGS $INDEXER_C_FLAGS"

    if [[ "${flags//-${opt}//}" == "${flags}" ]]; then
        #No arguments with -${opt}// found, return early
        return
    fi

    # Found at least one argument

    symbol_list=" "
    local flag
    for flag in $flags; do
        if [[ "x${flag#\-${opt}//}" != "x${flag}" ]]; then
            # Find the symbol that we want to add
            local symbol="${flag#\-${opt}//}"
            symbol="${symbol%=*}"
            # The symbol is not already in the list of symbols
            if [[ "${symbol_list/ $symbol /}" == "${symbol_list}" ]]; then
                symbol_list="${symbol_list}${symbol} "
                # Add it to the list, preserving wrapping spaces
                # " sym1 sym2 "
            fi
        fi
    done
    # Remove the space at the end, then remove the space at the front.
    symbol_list="${symbol_list# }"
    symbol_list="${symbol_list% }"
    echo "${symbol_list}"
}

old_process_buildaction()
{
    if [[ "$2" == "type=" ]]; then
        buildaction="$1"
    else
        buildaction="$1 $2"
    fi
}

checkForVariables()
{
    local varname
    for varname in $*; do
        if [[ -z "$(eval echo \$$varname)" ]]; then
            exit_with_error "No $varname set.  Right click on" \
                    "$PROJECT_NAME in the Project Explorer, select" \
                    "properties, C/C++Build, Environment, select All" \
                    "Configurations from the dropdown and set a" \
                    "$varname variable."
        fi
    done
}

save_build_state()
{
    if [[ "$buildaction" == "save" ]]; then
        if [[ "$subprojname" == "~~" ]]; then
            do_save_action
            exit
        else
            buildaction=build
        fi
    fi

    if [[ "$buildaction" == "incr" ]]; then
        buildaction=build
    fi
}

do_build_setup()
{
    local multiActionScript=
    find_multi_action_script multiActionScript $subprojname

    if [[ -e "$multiActionScript" ]]; then
        # Make sure any indexer settings from the existing project are wiped
        # so they can be reset to the default unless explicitly stated in the setup
        # callback function.
        unset INDEXER_C_COMPILER
        unset INDEXER_CXX_COMPILER
        unset INDEXER_CXX_FLAGS
        unset INDEXER_C_FLAGS
        export MINIMUM_ECLIPSE_RT_VERSION
        export MINIMUM_ECLIPSE_RT_VERSION_AT_SETUP

        source "$multiActionScript" -setup "$@"
        #After running the setup step, unescape any variables set there 
        remove_path_variable_legacy_escaping
        
        local title="Setup ${BANNER_LABEL:-Project}: $PROJECT_NAME"
        export PROJECT_SAVE_COUNT=
        getProjectSaveCount PROJECT_SAVE_COUNT
        verify_no_legacy_escaped_path_variables
        launch_xterm -title "$title" setup-project.sh
        exit
    else
        exit_with_error "Can't find the multi-action build script."
    fi
}

do_build_action()
{
    # Resource is a directory, no scanning
    dosync=true
    docommand=true

    # Is it a directory? then alter the build action
    if [[ -d "$srcunix" ]]; then
        adjust_build_action_directory
    fi

    # Are we just trying to get the compiler specs? no push / pull
    if isBuildActionGetCompilerSpecs; then
        rsyncdopull=false
        rsyncdopush=false
    fi

    if [[ "$subprojname" == "~~" ]]; then
        exit_with_error "This is an old project.  Please re-run setup" \
            "on this project to continue."

    fi

    # This value is gotten once and shared throughout this script.
    SUBPROJECT_EXCLUSION_RULE=
    getRsyncSubProjectExclusionRule SUBPROJECT_EXCLUSION_RULE

    UNDEF_SYMBOLS="$(get_symbol_list U)"
    DEFINE_SYMBOLS="$(get_symbol_list D)"

    if     [[ "${buildaction}" == "clean wipe" ]] && \
           [[ -n "$REMOTEPROJECTDIR" ]]; then
        trace_on
        ssh "$REMOTEBUILDUSER@$REMOTEBUILDHOST" rm -rf "$REMOTEPROJECTDIR"
        trace_off

        echo "The remote folder $REMOTEPROJECTDIR on $REMOTEBUILDHOST has been wiped."
        exit
    fi

    if    [[ -z "${SUBPROJECT_EXCLUSION_RULE}"            ]] && \
          [[ "${buildaction}" != "sync-in"                ]] && \
          [[ "${buildaction}" != "sync-out"               ]] && \
          [[ $rsyncdopush == true || $rsyncdopull == true ]]; then
        exit_with_error "rsync exclude file or rule not found for" \
             "${build_resource}, cannot build sub-project."
    fi

    # If this is a modern project with the new local header cache but still
    # has locally generated launches, get rid of them.
    if [[ -n "$LOCALHDRCACHE" ]] && [[ -d "$LOCALPROJECTDIR/.launches" ]]; then
        rm -rf "$LOCALPROJECTDIR/.launches"
    fi

    local pass
    for pass in {1..2}; do
        #echo "Syncing ${BINDEV}..."
        rsync $rsyncdefaultverbosity $outgoingrsyncopts -e ssh --delete \
            --exclude-from="$rsyncconfigdir/rsync-exclude" \
            "$srcbindir/" \
            "$REMOTEBUILDUSER@$REMOTEBUILDHOST:$BINDEV"
        local error_status=$?
        if [[ "$error_status" == "11" ]] || [[ "$error_status" == "12" ]]; then
            # rsync error status was 11 or 12, which is recoverable if we just
            # need to make the remote folder.
            show_warning "rsync couldn't connect, retrying..."
            make_remote_folder
        elif [[ "$error_status" != "0" ]]; then
            show_error "Rsync error $error_status, exiting."
            exit $error_status
        else
            break
        fi
    done

    if [[ "$dosync" == "true" ]] && [[ "$rsyncdopush" == "true" ]]; then
        echo "Sending outgoing changes for ${build_resource}"
        local mainbinlinks=
        handle_fake_local_binaries -getlist mainbinlinks
        if [[ -n "$mainbinlinks" ]]; then
            # Turn the : separated list of main bin links to a bunch of
            # rsync options and add them to the list of exclusions
            PUSH_RSYNC_OPTS="$PUSH_RSYNC_OPTS --exclude='/${mainbinlinks//:/' --exclude='/}'"
        fi
        local destpath="$REMOTEPROJECTDIR/$subprojname"

        eval "rsync $rsyncdefaultverbosity $outgoingrsyncopts -e ssh --delete" \
            "${PUSH_RSYNC_OPTS} ${SUBPROJECT_EXCLUSION_RULE}" \
            "--exclude-from='$rsyncconfigdir/rsync-exclude'" \
            "'$LOCALPROJECTDIR/$subprojname/'" \
            "'$REMOTEBUILDUSER@$REMOTEBUILDHOST:$destpath'"
        local error_status=$?
        if [[ "$error_status" != "0" ]]; then
            show_error "Rsync error $error_status, exiting."
            exit $error_status
        fi
    fi

    return
}

do_local_action()
{
    local multiActionScript=
    find_multi_action_script multiActionScript $subprojname

    pushd "$PROJECT_PATH/$subprojname" >& /dev/null

    local dobuild=false
    local doclean=false
    local dotest=false
    local args="$*"
    if [[ "${args#${REMOTE_SHELL_TARGET_NAME}}" != "$args" ]]; then
        : # Do nothing
    elif [[ "$1" == "yum" ]]; then
        do_yum_update_local "$@"
    elif [[ "$1" == "unsetup" ]]; then
        do_unsetup_local "$@"
    elif [[ -e "$multiActionScript" ]]; then
        while [[ -n "$1" ]]; do
            case $1 in
                build|-build|incr|save)
                    dobuild=true
                    shift
                    ;;
                clean|-clean)
                    doclean=true
                    shift
                    ;;
                test|-test)
                    dotest=true
                    shift
                    ;;
                *)
                    break
                    ;;
            esac
        done
        
        source "$multiActionScript" -dummy
        export MINIMUM_ECLIPSE_RT_VERSION
        export MINIMUM_ECLIPSE_RT_VERSION_AT_SETUP
        test_for_compatible_rt_version_during_build && \
        test_for_compatible_rt_version_at_setup_during_build &&
        test_for_downgrade_during_build
        
        local SUBPROJECTDIR=. && \
        echo && \
        echo source "$multiActionScript" -local "$@" && \
        source "$multiActionScript" -local "$@" && \
        echo
    fi
    local _status=$?
    popd >& /dev/null
    return ${_status}
}

do_remote_shell()
{
    local pauseAfter="" #"; pause"
    local args="$@"
    local title="ssh $REMOTEBUILDUSER@$REMOTEBUILDHOST"
    local sshcommand="ssh -t $REMOTEBUILDUSER@$REMOTEBUILDHOST"
    sshcommand="$sshcommand \"bash -l -c \\\"cd $REMOTEPROJECTDIR${subprojname:+/}${subprojname}; ${args}${args:+;} exec bash\\\"\""
    echo
    echo "Opening remote shell as $REMOTEBUILDUSER on $REMOTEBUILDHOST...."
    launch_xterm -title "$title" "eval '$sshcommand'$pauseAfter"
    update_header_cache
}

do_unsetup_local()
{
    echo
    echo "Starting unsetup ..."

    export PROJECT_SAVE_COUNT=
    getProjectSaveCount PROJECT_SAVE_COUNT
    local title="Unsetup of project $PROJECT_NAME"
    launch_xterm -title "$title" "setup-project.sh -unsetup"

    if [[ ! -e .settings ]]; then
        do_local_action clean all
        echo
        echo "Project has been reverted to initial state."
    else
        echo
        echo "Cancelled unsetup."
    fi
    # Get exit status   
    local status=$?
    return_skip_remote_action $status
}
do_yum_update_local()
{
    if [[ "$1 $2" == "yum update"  ]] || \
       [[ "$1 $2" == "yum install" ]] || \
       [[ "$1 $2" == "yum info"    ]] || \
       [[ "$1 $2" == "yum list"    ]] || \
       [[ "$1 $2" == "yum remove"  ]]; then
        shift
        # Allow targets named "yum update <package>" to be passed to yum
        ssh "$REMOTEBUILDUSER@$REMOTEBUILDHOST" \
                  "yum --assumeyes clean all &&" \
                  "yum --assumeyes $*" && \
        update_header_cache

        # Get exit status   
        local status=$?

        # Be sure to set the resource responsible for the yum
        # update to be the multi-action-script, if it exists
        local multiActionScript=
        find_multi_action_script multiActionScript $subprojname
        if [[ -e "$multiActionScript" ]]; then
            set_stack_frame_location -file "$multiActionScript"
        fi
        if [[ $status == 0 ]]; then
            show_info "Yum $1 succeeded"
        else
            show_error "Yum $1 failed."
        fi
        return_skip_remote_action $status
    fi
}

do_remote_action()
{
    if [[ "$docommand" == "true" ]]; then
        echo "$buildcommand"

        config_resource "$resource"
        echo   remote-action.sh -build "$resource" $buildaction
        source remote-action.sh -build "$resource" $buildaction
    fi

    if [[ "${buildaction#${REMOTE_SHELL_TARGET_NAME}}" != "$buildaction" ]]; then
        shift $(echo "${REMOTE_SHELL_TARGET_NAME}" | wc -w)
        do_remote_shell "$@"
    fi

    # Are we just trying to get the compiler specs? no push / pull
    if isBuildActionGetCompilerSpecs; then
        rsyncdopull=false
        rsyncdopush=false
    fi

    if [[ "$dosync" == "true" ]] && [[ "$rsyncdopull" == "true" ]]; then
        local inb_exclude
        local inb_suproject_exclusion_rule
        # If we have a core file specified, then we may have an inbound
        # sync to get the source code to line up, thus we can suppress the
        # inbound sync exclusion of C source code.
        if [[ "$docommand" == "true" ]] && [[ -z "$COREFILE" ]]; then
            # If we were doing a build action, we should add special
            # exclusions to inbound sync to protect us from accidentally
            # overwriting files we are editing, like C and C++ source and
            # header files.  If we are doing a pure sync-in, we don't want
            # to add this extra exclusion filter.
            inb_exclude="--exclude-from='$rsyncconfigdir/rsync-inbound-exclude'"

            # This value is gotten once and shared throughout this script.
            getRsyncSubProjectExclusionRule inb_subproject_exclusion_rule -inbound

        else
            # If we are not doing a build, and thus it is a pure inbound
            # sync, we don't want to protect against importing source and
            # headers and thus we will use a bogus extra argument since using
            # "" does not work, thus let's exclude a bogus pattern that should
            # never occur in the real world.
            inb_exclude=""
            inb_subproject_exclusion_rule=""
        fi
        echo
        echo "Collecting incoming changes for ${build_resource}"
        local destpath="$REMOTEPROJECTDIR/$subprojname"

        eval "rsync $rsyncdefaultverbosity $incomingrsyncopts -e ssh --delete" \
            "${PULL_RSYNC_OPTS} ${SUBPROJECT_EXCLUSION_RULE}" \
            "--exclude-from='$rsyncconfigdir/rsync-exclude'" \
            "${inb_subproject_exclusion_rule} $inb_exclude" \
            "'$REMOTEBUILDUSER@$REMOTEBUILDHOST:$destpath/'" \
            "'$LOCALPROJECTDIR/$subprojname'"
        if [[ "$docommand" == "true" ]]; then
            # If we did an inbound sync, let's look for markers indicating
            # where we need to link to bash, and if so, do it.
            handle_fake_local_binaries -create
            # For non-gcc remotes, it is important to always update the header
            # cache on a build or test action.
            if    ! remote_build_uses_gcc && \
                  [[ ( "${buildaction/build/}" != "$buildaction" ) ||
                     ( "${buildaction/test/}"  != "$buildaction" ) ]]; then
                update_header_cache
                echo
            fi
        fi
    fi

    return
}

make_remote_folder()
{
    # Note BINDEV is within REMOTEPROJECTDIR
    show_info "Creating the remote folder '$BINDEV'"

    # Connecting the remote machine to make the folder
    local line="mkdir -p $BINDEV >& /dev/null;"

    ssh -C $REMOTEBUILDUSER@$REMOTEBUILDHOST \
        "bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$line'"

    if [[ "$?" != "0" ]]; then
        wait_then_exit_with_error "Could not connect to $REMOTEBUILDHOST"
    fi
}

adjust_build_action_directory()
{
    if [[ "${buildaction#${REMOTE_SHELL_TARGET_NAME}}" != "$buildaction" ]]; then
        docommand=false
    elif [[ "$buildaction" == "save" ]]; then
        docommand=false
    elif [[ "$buildaction" == "sync-in" ]]; then
        docommand=false
        rsyncdopush=false
    elif [[ "$buildaction" == "sync-out" ]]; then
        docommand=false
        rsyncdopull=false
    fi

    if [[ "${build_resource}" == "$resource" ]]; then
        if [[ "$buildaction" == "save" ]]; then
            # echo Resource is a project folder. Suppressing syncing/building...
            dosync=false
            # exit
        fi
        if [[ "$buildaction" == "incr" ]]; then
            docommand=true
        fi
    fi
}

do_save_action()
{
    echo
    echo Local save only. Done.
}

check_compiler_specs()
{
    spec_file="${resource##*/}"
    resource=""
    #echo spec_file is [$spec_file]
    #echo spec file is [$resource]
}

add_compiler_options()
{
    compiler=$1
    shift
    compiler_args="$@"
    #echo compiler is $compiler
    #echo compiler_args: $*

    # Make sure INDEXER_CXX_COMPILER and INDEXER_C_COMPILER have
    # no legacy escaping
    verify_no_legacy_escaped_path_variables
    set_indexer_preferences

    # Get compiler specific flags from the project
    if [[ "$compiler" == "g++" ]]; then
        compiler_args="$compiler_args $INDEXER_CXX_FLAGS"
        compiler="${INDEXER_CXX_COMPILER}"
    elif [[ "$compiler" == "gcc" ]]; then
        compiler_args="$compiler_args $INDEXER_C_FLAGS"
        compiler="${INDEXER_C_COMPILER}"
    fi

    # Translate all escaped quotes to unescaped ones (we will re-escape them
    # below
    compiler_args="${compiler_args//\\\"/\"}"

    # Translate all "//somepath" to "/somepath"
    compiler_args="${compiler_args//\"\/\//\"/}"

    #Be sure to escape all quotes with a preceding backslash
    buildaction="$buildaction $compiler $spec_file ${compiler_args//\"/\\\"}"
}

return_skip_remote_action()
{
    SKIP_REMOTE_ACTION=true
    return $*
}

build_main()
{
    # Make sure all variables have legacy escaping removed.
    verify_no_legacy_escaped_path_variables

    set_build_preferences

    local target_resource=""

    # Note that the PROJECT_PATH folder may not necessarily end in the
    # project name, so the substitution must take that into effect.
    if [[ "$PWD" != "${PWD#$PROJECT_PATH}" ]]; then
        target_resource="/${PROJECT_NAME}${PWD#$PROJECT_PATH}"
    fi

    if [[ "$1" == "-sr" ]]; then
        # When the first argument is -sr for selected resource, either
        if [[ "$3" == "-action" ]]; then
            resource="$2"
            shift 3
        elif [[ "$2" == "-action" ]]; then
            resource=""
            shift 2
        else
            exit_with_error "Expected -action argument not found."
        fi
        buildaction=$1
    elif [[ "$3" == "type=" ]]; then
        # For old get compiler specs action...
        resource="$1"
        shift
        buildaction="$1"
    elif [[ "$2" == "~~" ]]; then
        # For the old projects, either first argument is the resource
        # and then 2nd is ~~ ...
        resource="$1"
        shift 2
        old_process_buildaction ${*//=/= } "type="
    elif [[ "$1" == "~~" ]]; then
        # For the old projects , if there is no resource, then the 1st is ~~
        resource=""
        shift
        old_process_buildaction ${*//=/= } "type="
    elif [[ "$1" == "setup" ]]; then
        buildaction=setup
        shift
    else
        buildaction="$*"
    fi

    if isBuildActionGetCompilerSpecs; then
        shift
        if [[ "$1" == "type=" ]]; then
            shift
        fi
        check_compiler_specs "$@"
    fi

    # We want to make sure that a) a resource is supplied and
    # within the project otherwise, we use the target as the resource.
    if    [[ -n "$resource" ]] && \
          [[ "${resource}" != "${resource#/$PROJECT_NAME}" ]]; then
        echo resource is ["$resource"]
    else
        resource="$target_resource"
        echo target is [$resource]
    fi

    config_resource "$resource"

    if [[ "${buildaction}" == "setup" ]]; then
        do_build_setup "$@"
    fi

    checkForVariables REMOTEBUILDUSER REMOTEBUILDHOST
    universal_local_config

    if isBuildActionGetCompilerSpecs; then
        add_compiler_options "$@"
    else
        echo -n "activeconfig|buildaction|build_resource is "
        echo    "[$ACTIVECONFIG|$buildaction|$build_resource]"
    fi


    # These rsync options can be set to exclude files and then
    # used in do_build_action (for push) and do_remote_action (for pull)
    PUSH_RSYNC_OPTS=
    PULL_RSYNC_OPTS=
    SKIP_REMOTE_ACTION=false

    save_build_state
    setup_project_ignore_files
    do_local_action "$@"
    local status=$?
    if [[ "$status" != "0" ]]; then
        show_error "do_local_action failed."
        exit $status
    elif [[ $SKIP_REMOTE_ACTION == true ]]; then
        exit $status
    fi
    
    do_build_action
    do_remote_action "$@"

    if ! isBuildActionGetCompilerSpecs; then
        echo "$ACTIVECONFIG configuration $buildaction" \
            "of ${build_resource} done on $REMOTEBUILDHOST."
    fi
}

handle_fake_binaries_inner_loop()
{
    local firstone=true
    local searchpath=${1%/}
    local action=$2
    find "$searchpath" -name ".*.binhere" | \
    while read hereFile; do
        # Make a link to bash in the location of the here file,
        # with the dot stripped off from the file name (but in the same path)
        local mainbinlink="${hereFile%/*}/${hereFile##*/.}"
        # And then remove the .binhere suffix itself
        mainbinlink="${mainbinlink%.binhere}"
        case $action in
            create)
                makeBashLink "${mainbinlink}"
                ;;
            getlist)
                if [[ "$firstone" == "true" ]]; then
                    firstone=false
                else
                    echo -n ":"
                fi
                echo -n "${mainbinlink#$searchpath/}"
                ;;
        esac
    done
    if [[ "$action" == "getlist" ]]; then
        echo
    fi
}

handle_fake_local_binaries()
{
    local varname=
    local _result=
    local action=
    case $1 in
        -create)
            action=create
            ;;
        -getlist)
            action=getlist
            varname=$2
            if [[ -z "$varname" ]]; then
                exit_with_error "$FUNCNAME: Must supply varname with -getlist"
            fi
            ;;
        *)
            exit_with_error "$FUNCNAME: Must supply action."
            ;;
    esac

    local searchpath="$LOCALPROJECTDIR/$subprojname/"


    if [[ "$action" == "getlist" ]]; then
        # We need to use an inner loop and process output, because
        # if not we can't access its variables. Process substitution is
        # not an option here.
        _result="$(handle_fake_binaries_inner_loop "$searchpath" "$action")"
    else
        # Otherwise, we can just call the loop and sent the output (if any)
        # to standard out and error.
        handle_fake_binaries_inner_loop "$searchpath" "$action"
    fi

    # If we are returning a value, set it before leaving.
    if [[ -n "$varname" ]]; then
        eval "$varname='${_result}'"
    fi
}

test_for_compatible_rt_version_during_build()
{
    if ! is_current_eclipse_rt_version_compatible; then
        local minVer=$(get_minimum_eclipse_rt_version)
        exit_with_error "$FUNCNAME: The current version of Eclipse for Remote Targets is NOT" \
        "compatible with this project.  The minimum version required by this project is $minVer." \
        "Please update your Eclipse for Remote Targets and try again."
    fi
}

test_for_compatible_rt_version_at_setup_during_build()
{
    if ! is_eclipse_rt_version_at_setup_compatible; then
        local minVer=$(get_minimum_eclipse_rt_version_at_setup)
        exit_with_error "$FUNCNAME: The version of Eclipse for Remote Targets used to" \
        "setup this project is NOT compatible with this project.  The minimum version" \
        "required to setup this project is $minVer.  Please re-run setup on this" \
        "project and then try again."
    fi
}

test_for_downgrade_during_build()
{
    if is_eclipse_rt_version_setup_downgrade; then
        show_warning "$FUNCNAME: This project was set up with a newer version of" \
            "Eclipse for Remote Targets (version ${ECLIPSE_RT_VERSION_AT_SETUP})." \
            "Re-run setup to eliminate this warning."
    fi
}

build_main "$@"
