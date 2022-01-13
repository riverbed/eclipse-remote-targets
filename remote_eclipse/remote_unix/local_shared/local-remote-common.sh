#! /bin/bash
#
# local-remote-common.sh -- Common functions shared across scripts
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source local-remote-common-aliases.sh

### BEGIN INCLUDE GUARD ###
if [[ "${LOCAL_REMOTE_COMMON_SOURCED}" == "true" ]]; then
    return
fi
export LOCAL_REMOTE_COMMON_SOURCED=true
### END INCLUDE GUARD ###

export ECLIPSE_RT_VERSION=2.1.0
export ECLIPSE_RT_RELEASE_NAME=carroll

export SUPPRESS_ERROR_LINE_NUMBERS=

export REMOTE_PRE_EXEC

# If the launch script does not support a particular method
# we need a standard status code to indicate a method is not
# implemented.
export ACTION_NOT_IMPLEMENTED=44

export _TAB=$'\t'

# BSD doesn't support version, and even if it does, it doesn't say GNU.
export SED_TYPE=$(sed --version 2> /dev/null | head -n 1)
# If any part of the version line mentions GNU, it's GNU sed.
if [[ "${SED_TYPE}" != "${SED_TYPE/GNU/}" ]]; then
    SED_TYPE=GNU
else
    SED_TYPE=BSD
fi

setErrorStatus()
{
    return $1
}

# Set the line-buffering sed switch for sed_u
if [[ "$SED_TYPE" == "GNU" ]]; then
    export LINEBUFSEDSWITCH=-u
else
    # For most, this will be -l.  For ancient BSD, it will be blank.
    export LINEBUFSEDSWITCH=$(echo -e -l | sed -l -e "" 2> /dev/null)
fi

suppress_error_line_numbers()
{
    SUPPRESS_ERROR_LINE_NUMBERS=true
}

debug_echo()
{
    :
    # echo "$@"
}

show_info()
{
    set_stack_frame_location
    echo "${STACK_FRAME_LOCATION}: info: $@" 1>&2
    unset STACK_FRAME_LOCATION
}

show_error()
{
    set_stack_frame_location
    local prefix=
    if [[ -n "$BINDEV" ]] || [[ -n "$PROJECT_NAME" ]]; then
        if [[ -z "$SUPPRESS_ERROR_LINE_NUMBERS" ]]; then
            prefix="${STACK_FRAME_LOCATION}: error: "
        fi
    fi
    echo "${prefix}$@" 1>&2
    unset STACK_FRAME_LOCATION
}

set_stack_frame_location()
{
    # Allow support to force the error to be on a particular file
    if [[ "$1" == "-file" ]]; then
        STACK_FRAME_LOCATION="$2:0"
        shift 2
    fi

    if [[ -z "$STACK_FRAME_LOCATION" ]]; then
        local stack_size=${#FUNCNAME[@]}
        # to avoid noise we start with 2 to skip the set_stack_frame_location
        # and whomever called it
        for (( i=2; i<$stack_size; i++ )); do
            local func="${FUNCNAME[$i]}"
            if [[ -z "$func" ]]; then
                func=MAIN
            fi
            local linen="${BASH_LINENO[$(( i - 1 ))]}"
            local src="${BASH_SOURCE[$i]}"
            debug_echo "$i) $src:$linen:$func"
            if [[ -n "$src" ]]; then
                STACK_FRAME_LOCATION="$src:$linen"
                break
            fi
        done
        if [[ -z "$STACK_FRAME_LOCATION" ]]; then
            STACK_FRAME_LOCATION="$0:${BASH_LINENO[1]}"
        fi
    fi
}

exit_with_error()
{
    set_stack_frame_location
    show_error "$@"
    exit 2
}

pause_and_exit_with_error()
{
    set_stack_frame_location
    show_error "$@"
    echo
    pause
    exit 2
}

wait_then_exit_with_error()
{
    set_stack_frame_location
    sleep 0.3
    echo 1>&2
    exit_with_error "$@"
}

wait_then_show_warning()
{
    set_stack_frame_location
    sleep 0.3
    echo 1>&2
    echo "${STACK_FRAME_LOCATION}: warning: $@" 1>&2
    unset STACK_FRAME_LOCATION
}

show_warning()
{
    set_stack_frame_location
    echo "${STACK_FRAME_LOCATION}: warning: $@" 1>&2
    unset STACK_FRAME_LOCATION
}

sedInPlace()
{
    if [[ "$SED_TYPE" == "GNU" ]]; then
        sed -i'' "$@"
    else
        sed -i '' "$@"
    fi
}

find_multi_action_script()
{
    local varname=$1
    local subprojname=$2
    shift 2

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    if [[ -z "$subprojname" ]]; then
        exit_with_error "$FUNCNAME: Must supply a subproject name."
    fi

    local scriptNames="remote_eclipse_build.sh"

    local _result=""

    local searchLoc="$PROJECT_PATH/$subprojname"
    searchLoc="${searchLoc%/.}"

    local scriptName=
    for scriptName in $scriptNames; do
        local scriptLoc="$searchLoc/$scriptName"
        if [[ -e "$scriptLoc" ]]; then
            _result="$scriptLoc"
            
            # Make sure build scripts have their execute bit set.
            if [[ ! -x "$scriptLoc" ]]; then
                chmod +x "$scriptLoc"
            fi
            break
        fi
    done

    if [[ -z "${_result}" ]] && [[ "$subprojname" != "." ]]; then
        scriptName="remote_eclipse_build_${subprojname//\//.}.sh"
        local foundScript="$(which "$scriptName" 2> /dev/null)"
        if [[ -n "$foundScript" ]]; then
            _result="$foundScript"
        fi
    fi

    eval "$varname='${_result}'"
}

snake_to_camel_case()
{
    # Takes a variable output name and a string and converts snake case to
    # camel case
    local varname=$1
    local text=$2
    local _result=
    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name ant text."
    fi

    local cap_next=true

    local i=0
    while [[ "$i" != "${#text}" ]]; do
        local ch="${text:${i}:1}"
        let i=$i+1
        case $ch in
            _)
                cap_next=true
                ;;
            *)
                if [[ $cap_next == true ]]; then
                    _result="${_result}$(echo -e "$ch" | tr '[a-z]' '[A-Z]')"
                    cap_next=false
                else
                    _result="${_result}$ch"
                fi
                ;;
        esac
    done
    eval "$varname='${_result}'"
}

prepend_text_in_file()
{
    local file="$1"
    local marker="$2"
    local text="$3"
    shift 3

    if [[ -z "$file" ]]; then
        exit_with_error "$FUNCNAME: Must supply file."
    fi

    if [[ -z "$marker" ]]; then
        exit_with_error "$FUNCNAME: Must supply marker."
    fi

    if [[ -z "$text" ]]; then
        exit_with_error "$FUNCNAME: Must supply text."
    fi

    local pre_marker=""
    local esc_marker="$marker"
        
    # If the marker starts with a beginning of line symbol, place it
    # before the (block) parentheses: "^(block)" not "(^block)"
    if [[ "${esc_marker}" != "${esc_marker#^}" ]]; then
        esc_marker="${esc_marker#^}"
        pre_marker="^"
    fi
    esc_marker="${esc_marker//@/\\@}"
    esc_marker="${esc_marker//[/\\[}"
    esc_marker="${esc_marker//]/\\]}"

    local esc_text="$text"
    esc_text="${esc_text//\"/\\\"}"

    sedInPlace -e "s@${pre_marker}\\(${esc_marker}\\)@${esc_text}\1@" \
               -e 's/_~_/\'$'\n/g' "$file"
}

get_remote_gdb_bin()
{
    local varname=$1

    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    # Make sure REMOTE_GDB_BIN has no legacy escaping
    verify_no_legacy_escaped_path_variables

    local _result=${REMOTE_GDB_BIN}
    _result=${_result:-gdb}

    eval "$varname='${_result}'"
}

function_exists()
{
    # Check if a function exists
    declare -f -F $1 > /dev/null
    return $?
}

build_dispatcher()
{
    if [[ "$1" != "-prefix" ]] || [[ -z "$2" ]]; then
        exit_with_error "$FUNCNAME: usage -prefix <prefix> [build options...]"
    fi
    local prefix="$2"
    shift 2

    local action="${1#-}"
    case "$1" in
        -local|-setup|-remote|-get-rsync-exclusion-rule|-get-rsync-inbound-exclusion-rule|-get-build-output-filter|-variables-and-targets)
            shift
            local function_name="${prefix}_${action//-/_}"
            if ! function_exists ${function_name}; then
                return $ACTION_NOT_IMPLEMENTED
            fi
            $function_name "$@"
            return
            ;;
    esac
    # If a callback action is unrecognized, return ACTION_NOT_IMPLEMENTED
    return $ACTION_NOT_IMPLEMENTED
}

get_launch_file_environment_variables()
{
    local launchFile="$1"
    shift
    if [[ ! -e "$launchFile" ]]; then
        exit_with_error "$FUNCNAME: Launch file must be supplied"
    fi
    local prefix="$1"
    local launchVars=$(cat "$launchFile" | tr -d '\r' | \
               sed -n "\\#^<mapAttribute .*environmentVariables\">\$#,\\#^</mapAttribute>\$#p" | \
               sed -n '/^<\/\{0,1\}mapAttribute/!p' | \
               sed "s#^<mapEntry key=\"\\([_A-Za-z0-9]*\\)\" value=\"\\(.*\\)\"/>\$#${prefix}\\1=\"\\2\"#;s#\"/>\$##" | \
               sed "s#\\\\#\\\\\\\\#g;s#&quot;#\\\\\"#g;s#&amp;#\\&#g" | tr '\n' ';')
    eval "${launchVars%;}"
}

set_launch_file_environment_variable()
{
    local launchFile="$1"
    shift
    if [[ ! -e "$launchFile" ]]; then
        exit_with_error "$FUNCNAME: Launch file must be supplied"
    fi
    local invarname=$1
    shift
    if [[ -z "$invarname" ]]; then
        exit_with_error "$FUNCNAME: Variable name must be supplied"
    fi
    local outvarname=$invarname
    if [[ -n "$1" ]]; then
        outvarname=$1
        shift
    fi
    
    if [[ -n "$(eval echo "\${!$invarname[@]}")" ]]; then
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$invarname)"
        varvalue="${varvalue//\&/&amp;}"
        varvalue="${varvalue//\"/&quot;}"
        varvalue="${varvalue//\\/\\\\}"
        varvalue="${varvalue//\#/\\#}"
        varvalue="${varvalue//\&/\\&}"
        local pattern="s#^\\(<mapEntry key=\"$outvarname\" value=\"\\).*\\(\"/>\$\\)"
        pattern="${pattern}#\\1${varvalue}\\2#"
        sedInPlace "$pattern" "$launchFile"
    else
        local pattern="/^\\(<mapEntry key=\"$outvarname\" value=\"\\).*\\(\"\\/>\$\\)/d"
        sedInPlace "$pattern" "$launchFile"
        # We just may have removed a mapEntry.  Now let's see if none are left.  If so,
        # we should remove the mapAttribute markers
        if ! grep -q "^<mapEntry key=\"[A-Z_]" "$launchFile"; then
            # lets remove the <mapAttribute>
            pattern="\\#^<mapAttribute .*environmentVariables\">\$"
            pattern="${pattern}#,\\#^</mapAttribute>\$#"'!'"p"
            sedInPlace -n "${pattern}" "$launchFile"
        fi
    fi
}

rmdir_only_if_empty()
{
    trace_off
    # Does the folder exist?
    if [[ -d "$1" ]]; then
        if [[ "$(ls -A "$1")" ]]; then
            : # Folder is not empty
        else
            rmdir "$1"
        fi
    fi
}

remove_path_variable_legacy_escaping()
{
    local varlist=$(set | \
        sed -n -e "/^[A-Za-z_][A-Za-z0-9_]*=[']\\{0,1\\}[;][/]/p" | \
        sed "s/\\(^[A-Za-z_][A-Za-z0-9_]*\\)=.*$/\\1/")
    local varname=
    for varname in $varlist; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"
        # Strip off leading semicolon from older projects that use it
        # to protect against msys path changing: the triple-colon is more effective
        varvalue="${varvalue#;}"
        eval "$varname='${varvalue}'"
        debug_echo "$FUNCNAME: Unescaping $varname..." 
    done
}

get_normalized_version_string()
{
    local theVer=$1
    local theShiftVer="000${theVer}.0.0.0"
    local theMajorVer="${theShiftVer%%.*}"
    local theShiftVer="000${theShiftVer#*.}"
    local theMinorVer="${theShiftVer%%.*}"
    local theShiftVer="000${theShiftVer#*.}"
    local the2xDotVer="${theShiftVer%%.*}"
    
    local theNormVer="${theMajorVer: -3}_${theMinorVer: -3}_${the2xDotVer: -3}"
    echo "$theNormVer"
}

get_minimum_eclipse_rt_version()
{
    echo "${MINIMUM_ECLIPSE_RT_VERSION:-0.9}"
}

get_minimum_eclipse_rt_version_at_setup()
{
    if [[ -n "${MINIMUM_ECLIPSE_RT_VERSION_AT_SETUP}" ]]; then
        echo "${MINIMUM_ECLIPSE_RT_VERSION_AT_SETUP}"
    else
        get_minimum_eclipse_rt_version
    fi
}

is_current_eclipse_rt_version_compatible()
{
    local minimumVersion=$(get_normalized_version_string "$(get_minimum_eclipse_rt_version)")
    local currentVersion=$(get_normalized_version_string "${ECLIPSE_RT_VERSION:-0.0}")

    [[ ! ( "${currentVersion}" < "${minimumVersion}" ) ]]
}

is_eclipse_rt_version_setup_downgrade()
{
    local atSetupVersion=$(get_normalized_version_string "${ECLIPSE_RT_VERSION_AT_SETUP:-0.0}")
    local currentVersion=$(get_normalized_version_string "${ECLIPSE_RT_VERSION:-0.0}")
    
    [[ "${atSetupVersion}" > "${currentVersion}" ]]
}

is_eclipse_rt_version_at_setup_compatible()
{
    local minimumVersion=$(get_normalized_version_string "$(get_minimum_eclipse_rt_version_at_setup)")
    local atSetupVersion=$(get_normalized_version_string "${ECLIPSE_RT_VERSION_AT_SETUP:-0.0}")

    [[ ! ( "${atSetupVersion}" < "${minimumVersion}" ) ]] 
}

show_eclipse_rt_version_string()
{
    echo "Eclipse for Remote Targets" \
         "${ECLIPSE_RT_VERSION} (release_${ECLIPSE_RT_RELEASE_NAME})"
}

verify_no_legacy_escaped_path_variables()
{
    set_stack_frame_location
    local varlist=$(set | \
        sed -n -e "/^[A-Za-z_][A-Za-z0-9_]*=[']\\{0,1\\}[;][/]/p" | \
        sed "s/\\(^[A-Za-z_][A-Za-z0-9_]*\\)=.*$/\\1/" | tr '\n' ' ')
    if [[ -n "$varlist" ]]; then
        exit_with_error "$FUNCNAME: Variables '${varlist% }' are unescaped."
    fi
}

list_all_functions()
{
    case "$1" in
        -v|v*)
            #verbose
            set | grep '()' --color=always
            ;;
        *)
            declare -F | cut -d" " -f3 | egrep -v "^_"
            ;;
    esac
}

export_all_functions()
{
    export -f $(list_all_functions)
}

export_all_functions