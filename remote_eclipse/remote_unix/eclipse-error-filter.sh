#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source common-remote-functions.sh

ESC_PROJECT_PATH="${PROJECT_LOC//\\//}"
ESC_REMOTE_ECLIPSE_PATH="${REMOTE_ECLIPSE_LOC//\\//}"

calculate_path_filter()
{
    REMLOCSEDEXP=""
    # For cygwin platforms, apply a "pre-filter" to convert Visual Studio cl.exe
    # arguments to look like g++ commands
    if [[ "${OSTYPE}" == "cygwin" ]]; then
        # Use a filter to append individual g++/gcc lines after each cl.exe line,
        # one for each source file.
        PRE_FILTER=cat_unbuffered_convert_cl_exe_args
        REMLOCSEDEXP="$REMLOCSEDEXP;s#\\([A-Za-z]\\):\\\\#\\\\cygdrive\\\\\\L\\1\\\\#g"
        REMLOCSEDEXP="$REMLOCSEDEXP;s#\\([ \"]\\)\\([A-Za-z]\\):/#\\1/cygdrive/\\L\\2/#g"
        REMLOCSEDEXP="$REMLOCSEDEXP;s#\\\\\\([^\"]\\)#/\\1#g"
        REMLOCSEDEXP="$REMLOCSEDEXP;s@^[ ][ ]*[0-9][0-9]*[>]\\(.*\\)[(]\\([0-9][0-9]*\\)[)]"
        REMLOCSEDEXP="$REMLOCSEDEXP: \\([a-z][a-z ]*\\) \\(.*\\)\\[.*\\]@\\1:\\2: \\3: \\4@"
        REMLOCSEDEXP="$REMLOCSEDEXP;s#\\(:[0-9][0-9]*: [a-z][a-z]*:\\) :#\\1#"
    fi
    # Adding rule to take ctest error lines that mention a file and line
    # and suppress the leading 1: or 2: and then push it after the file name.
    # this allows errors to be annotations in the margins. 
    REMLOCSEDEXP="$REMLOCSEDEXP;s@^\([0-9][0-9]*:[ ]\)\(/.*:[0-9][0-9]*:[ ]\)@\2Test \1@"
    REMLOCSEDEXP="$REMLOCSEDEXP;s@^\([0-9][0-9]*:[ ]\)\(/.*\)[(]\([0-9][0-9]*\)[)]\(:[ ]\)@\2:\3\4Test \1@"

    REMLOCSEDEXP="$REMLOCSEDEXP;s@$REMBINDEVPATH@$LOCBINDEVPATH@"
    REMLOCSEDEXP="$REMLOCSEDEXP;s@$ABSREMPRJPATH@$LOCPRJPATH@g"
    REMLOCSEDEXP="$REMLOCSEDEXP;s@$ABSREMDEVPATH@$LOCDEVPATH@g"
    REMLOCSEDEXP="$REMLOCSEDEXP;s@$REMPRJPATH@$LOCPRJPATH@g"
    REMLOCSEDEXP="$REMLOCSEDEXP;s@$REMDEVPATH@$LOCDEVPATH@g"

    INCLUDESEDEXP=""

    local symbol
    for symbol in $UNDEF_SYMBOLS; do
        INCLUDESEDEXP="$INCLUDESEDEXP;s@\([ ]-D[ ]*\)\($symbol\)@ -U\2\1___\2@g"
    done
    for symbol in $DEFINE_SYMBOLS; do
        INCLUDESEDEXP="$INCLUDESEDEXP;s@\([ ]-D[ ]*\)\($symbol\)@\1___\2@g"
    done
    INCLUDESEDEXP="$INCLUDESEDEXP;s@\([ ]-D[ ]*[_A-Za-z][_A-Za-z0-9]*\)@\1=1~~@g;s@=1~~=@=@g;s@1~~@1@g"

    local prev_pattern=""
    local remotehdrpaths="$1"
    shift
    local pattern=""
    IFS=":"
    for pattern in $remotehdrpaths; do
        if [ "${pattern#\/usr/lib/gcc/}" != "${pattern}" ]; then
            pattern="${pattern%\/include}"
        fi
        # We only add no replacement patterns when they aren't a substring
        # of the previous one.  We are assuming the list is passed in sorted,
        # which it will be.  NOTE: that this algorithm is slightly different
        # than the one used during project setup; in that case we allow
        # subfolders that are unique if the parent folder isn't included.  Here
        # if two subfolders are unique but one has a longer basename than the
        # other, we only count the first one since we don't want to match the
        # same pattern string twice.
        if [ "${pattern#${prev_pattern}}" == "${pattern}" ]; then
            local escPattern="$pattern"
            local escPattern="${escPattern//(/[(]}"
            local escPattern="${escPattern//)/[)]}"
            local escPattern="${escPattern//./\\.}"
            REMLOCSEDEXP="$REMLOCSEDEXP;s@\([ =]\)\($escPattern\)@\1${remote_platform}\2@g"
            REMLOCSEDEXP="$REMLOCSEDEXP;s@\([ ]-I[ ]*[\"]\\{0,1\\}\)\($escPattern\)@\1${remote_platform}\2@g"
            prev_pattern="${pattern}"
        fi
    done
    unset IFS

    # If the project has a space in the path, be sure to wrap the include
    # options with quotes to help the Eclipse indexer find the path.
    if [ "${LOCDEVPATH// /_}" != "${LOCDEVPATH}" ]; then
        INCLUDESEDEXP="$INCLUDESEDEXP;s@\(-I[ ]*\)\(${LOCDEVPATH}/[-_+.A-Za-z0-9][^ ]*\)@\1\"\2\"@g"
        # Also add a filter for STDOUT and STDERR for commands that use the
        # path, but have a space before the argument, such as cd, ln -s, etc.
        # Make pattern below not match at the beginning of line,
        # since the include search list should not have quote wrapping, and
        # looks like a space followed by a path at the begining of the line
        REMLOCSEDEXP="$REMLOCSEDEXP;s@^[ ]@~LSP~@"
        REMLOCSEDEXP="$REMLOCSEDEXP;s@\([ =]\)\(${LOCDEVPATH}/[-_+.A-Za-z0-9][^ ]*\)@\1\"\2\"@g"
        REMLOCSEDEXP="$REMLOCSEDEXP;s@^~LSP~@ @"
    fi

    # If the remote platform cache location has a space in the path, be sure
    # to wrap the include options with quotes to help the Eclipse indexer
    # find the path.
    if [ "${remote_platform// /_}" != "${remote_platform}" ]; then
        INCLUDESEDEXP="$INCLUDESEDEXP;s@\(-I[ ]*\)\(${remote_platform}/[-_+.A-Za-z0-9][^ ]*\)@\1\"\2\"@g"
    fi

    local multiActionScript=
    find_multi_action_script multiActionScript $SUBPROJECT

    ADDEDSEDEXP=""
    if [[ -e "$multiActionScript" ]]; then
        local added_sedexp="$($multiActionScript -get-build-output-filter)"
        if [[ -n "${added_sedexp}" ]]; then
            ADDEDSEDEXP="${added_sedexp}"
        fi
    fi

    REMLOCSEDEXP="${REMLOCSEDEXP#;}"
    INCLUDESEDEXP="${INCLUDESEDEXP#;}"
}

compute_filter()
{
    REMBINDEVPATH=$BINDEV
    LOCBINDEVPATH="$ESC_REMOTE_ECLIPSE_PATH/remote_unix"

    REMPRJPATH=${REMOTEPROJECTDIR}
    LOCPRJPATH=${ESC_PROJECT_PATH}
    ABSREMPRJPATH="$(cd "$REMPRJPATH"; pwd -P)"
    REMDEVPATH=${REMOTEPROJECTDIR%/*}
    LOCDEVPATH=${ESC_PROJECT_PATH%/*}
    ABSREMDEVPATH="$(cd "$REMDEVPATH"; pwd -P)"

    # Make sure LOCALHDRCACHE and REMOTEHDRPATHS have no legacy escaping
    verify_no_legacy_escaped_path_variables

    remote_platform="${ESC_REMOTE_ECLIPSE_PATH%/*}/${LOCALHDRCACHE#/}"
    # Change all separating semicolons to separating colons
    REMOTEHDRPATHS="${REMOTEHDRPATHS//;/:}"

    calculate_path_filter "$REMOTEHDRPATHS"
}

process_cl_exe_line()
{
    # The first argument is the entire line
    local cl_line="$1"
    shift
    
    local args="-c"
    
    # All remaining arguments are the line, split by whitespace
    while [[ -n "$1" ]]; do
        # Visual Studio is assumed to be like C++11
        local compiler="g++ -std=c++11"
        local source_file=
        local pre_arg=
        local arg="$1"
        shift
        case $arg in
            *.[Cc][Pp][Pp]|*.[Cc][Cc]|*.[Cc][Xx][Xx])
                source_file="$arg"
                ;;
            *.[Cc])
                source_file="$arg"
                compiler=gcc
                ;;
            /D|/I|/U)
                pre_arg="-${arg#/}"
                arg="$1"
                shift
                ;;
            /D*|/I*|/U*)
                pre_arg="-${arg:1:1}"
                arg="${arg:2}"
                ;;
        esac
        if [[ -n ${pre_arg} ]]; then
            if [[ "${arg#\"}" != "${arg}" ]]; then
                arg="${arg#\"}"
                # If windows arguments start with a quote, we concatenate
                # consequtive arguments until they end with a quote (but not a
                # backslash escaped quote, which would mean to continue)
                while   [[ "${arg%\"}" == "${arg}" ]] || \
                        [[ "${arg%\\\"}" != "${arg}" ]]; do
                    arg="$arg $1"
                    shift
                done
                arg="${arg%\"}"
            fi
            args="$args ${pre_arg}${arg}"
        fi
        if [[ -n ${source_file} ]]; then
            if [[ "${source_file/ /}" != "${source_file}" ]]; then
                source_file="\"${source_file}\""
            fi
            # Get the leading whitespace
            local leading_spaces="${cl_line%%[^ ]*}"
            echo "${leading_spaces}[from CL for indexer] $compiler $args ${source_file}"
        fi
    done
}

cat_unbuffered_convert_cl_exe_args()
{
    local line=
    local status=
    while IFS= read -r line; do
        echo "$line"
        case \\$line in
            *[\>\ \\\"\'][Cc][Ll][.][Ee][Xx][Ee][\ \'\"]*)
                process_cl_exe_line "$line" $line
                shift
                ;;
        esac
    done
    status=$?
    # While emulating cat, did we have a partial line left? Write it out
    if [[ -n "$line" ]]; then
        echo -n "$line"
    fi
    return $status
}
# By default, use no pre-filter simply cat unbuffered
PRE_FILTER="cat -u"

compute_filter "$@"

{ "$@" 2>&1 >&3 | \
sed_unbuf -e "$ADDEDSEDEXP" -e "$REMLOCSEDEXP" >&2; } 3>&1 | \
${PRE_FILTER} | \
sed_unbuf -e "$ADDEDSEDEXP" -e "$REMLOCSEDEXP" | \
sed_unbuf "$INCLUDESEDEXP"
exit ${PIPESTATUS[0]}
