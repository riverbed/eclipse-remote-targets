#! /bin/bash
#
# remote-action.sh -- Main remote-action command
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# Header files
source common-functions.sh

saveExecOutput()
{
    # May be overriden by sourcing output handlers for other modules.
    false
}

handle_saved_output_options()
{
    : # Do nothing
}

add_remote_environment_variables()
{
    local varname
    for varname in $*; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"
        if [[ -n "$varvalue" ]]; then
            # if arguments have quotes, properly escape them
            varvalue="${varvalue//\\/\\\\}"
            varvalue="${varvalue//\"/\\\"}"
            envset="$envset; export $varname=\"\"\"$varvalue\"\"\""
        fi
    done
}

add_remote_environment_common()
{
    local REMOTE_PATH_ADD="$BINDEV:$BINDEV/local_shared"
    # This variable is not exported, and used only when running ps locally
    if [[ -n "$REMOTE_ACTION_PPID" ]]; then
        envset="$envset; REMOTE_ACTION_PPID=$REMOTE_ACTION_PPID"
    fi
    envset="$envset; export PATH=\"\"\"${REMOTE_PATH_ADD}:\$PATH\"\"\""
    add_remote_environment_variables REMOTEPROJECTDIR LOCALPROJECTNAME \
        BINDEV RWSDIR REMOTEPROJECTDOTDOT
}

add_remote_environment_build()
{
    # These switches are only used when doing build or compiler spec stuff.

    add_remote_environment_variables ACTIVECONFIG ENABLEDEBUGBUILD \
        REMOTEDEPLOYUSER REMOTEDEPLOYHOST COREFILE CUSTOM_BUILD_OPTS \
        REMOTEHDRPATHS PROJECT_LOC WORKSPACE_LOC REMOTE_ECLIPSE_LOC \
        UNDEF_SYMBOLS DEFINE_SYMBOLS LOCALHDRCACHE REMOTE_PRE_EXEC \
        LOCAL_DEBUGGER_WRAPPER
        
}

add_remote_environment_exec()
{
    add_remote_environment_variables EXECSW EXECWD BINALIAS SHOW_EXEC_PARAMS \
        MAINBINPATH MAINBINSUBDIR MAINBINLTSUBDIR MAINBINARY lt_MAINBINARY \
        SUBPROJECT
}

construct_remote_command()
{
    local envset=
    add_remote_environment_common
    if [[ "$actionMode" == "build" ]]; then
        add_remote_environment_build
        remotecommand="${envset#; }; exec do-action.sh $subprojname $*"
    else
        # Sometimes Eclipse inserts arguments when running our binaries
        # for example with test runners.  We want to see those added arguments
        # and pass them on.
        if [[ "$1" == "exec" ]] && [[ -n "$2" ]]; then
            shift
            add_trailing_arguments "$@"
        fi
        add_remote_environment_exec
        remotecommand="${envset#; }; exec exec-generic.sh"
    fi
}

add_trailing_arguments()
{
    while [[ -n "$1" ]]; do
        local arg="$1"
        shift
        # Does the arg need wrapping quotes (i.e., has a space)
        if [[ "${arg/ /}" != "${arg}" ]]; then
            arg="\"${arg}\""
        fi
        if [[ -n "$EXECSW" ]]; then
            EXECSW="${EXECSW} ${arg}"
        else
            EXECSW="${arg}"
        fi
    done
}

execute_remote_command()
{
    if [[ "$SHOW_EXEC_PARAMS" == "true" ]] || [[ "$actionMode" == "build" ]]; then
        echo "Executing Remote commands on $remotehost...."
        echo
    fi
    local outfile="$TMPDIR/$LOCALPROJECTNAME-output.txt"
    rm -f "$outfile"
    if saveExecOutput; then
        ssh -C $remoteuser@$remotehost "exec bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$remotecommand'" | \
            tee "$outfile"
        errorStatus="${PIPESTATUS[0]}"
        handle_saved_output_options "$outfile"
    else
        # Suppressing piping...
        ssh -C $remoteuser@$remotehost "exec bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }$remotecommand'"
        errorStatus=$?
    fi
    debug_echo "$FUNCNAME: errorStatus is $errorStatus"
    return $errorStatus
}

remote_action_main()
{
    # Make sure all variables have legacy escaping removed.
    verify_no_legacy_escaped_path_variables

    local actionMode=
    case "$1" in
        ~*~)
            # The legacy format of actionMode switches is ~actionMode~
            actionMode=${1//\~/}
            shift
            ;;
        -*)
            # The new format of actionMode switches is -actionMode
            actionMode=${1#-}
            shift
            ;;
    esac

    # Now require all callers of remote action to supply a mode
    if [[ -z "$actionMode" ]]; then
        show_error "No actionMode supplied"
    fi

    resource="$1"
    shift

    universal_local_config

    if [[ -n "$LAUNCH_ENV_SCRIPT" ]]; then
        local launchEnvScript="$LOCALPROJECTDIR/$SUBPROJECT/$LAUNCH_ENV_SCRIPT"
        if [[ -e "$launchEnvScript" ]]; then
            source "$launchEnvScript"
        fi
    fi

    if     [[ "$actionMode" != "build" ]] && \
           which "remote-exec-config-${SUBPROJECT//\//-}.sh" >& /dev/null; then
        # If a project type has its own execution configuration settings
        # source them here.
        source "remote-exec-config-${SUBPROJECT//\//-}.sh" \
            -$actionMode "$resource"
    fi

    remoteuser=$REMOTEBUILDUSER
    remotehost=$REMOTEBUILDHOST

    if [[ -z "$remoteuser" ]] || [[ -z "$remotehost" ]]; then
        show_error "No remote user or host specified," \
             "try building first."
        exit 1
    fi

    construct_remote_command "$@"
    execute_remote_command
    errorStatus=$?

    debug_echo "$FUNCNAME: errorStatus is $errorStatus"
    return $errorStatus
}

remote_action_main "$@"