#! /bin/bash
#
# common-remote-functions.sh -- Common functions shared across remote scripts
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

#Include the common headers shared between local and remote
source local-remote-common.sh

### BEGIN INCLUDE GUARD ###
if [[ "${COMMON_REMOTE_FUNCTIONS_SOURCED}" == "true" ]]; then
    return
fi
export COMMON_REMOTE_FUNCTIONS_SOURCED=true
### END INCLUDE GUARD ###

simplify_relative_path()
{
    local relativePath="$1"
    if [[ -d "$relativePath" ]]; then
        # If it's already a directory make the
        # basename the current directory which will
        # get stripped off at the end.
        local relativeDirName="$relativePath"
        local relativeBaseName="."
    else
        # It is a file, so the the directory part is
        # gotten by dirname.
        local relativeBaseName="$(basename "$relativePath")"
        local relativeDirName="$(dirname "$relativePath")"
    fi
    if [[ -d "$relativeDirName" ]]; then
        local realRelativeDirName="$(cd "$relativeDirName"; pwd)"
        local simplifiedRelativeDirName="${realRelativeDirName#$PWD/}"
        if [[ "$simplifiedRelativeDirName" != "$realRelativeDirName" ]]; then
            relativePath="$simplifiedRelativeDirName/$relativeBaseName"
        elif [[ "$realRelativeDirName" == "$PWD" ]]; then
            relativePath="$relativeBaseName"
        fi
    fi
    # Finally strip off any final "/." which was either added or naturally there
    echo "${relativePath%/.}"
}

find_binaries_in_dir()
{
    local binarydir="$1"
    if [[ ! -d "$binarydir" ]]; then
        exit_with_error "$FUNCNAME: Directory $binarydir doesn't exist."
    fi
    # Suppressing stderr because of errors about no such file or directory
    find "$binarydir" -type f -perm +111 -exec \
        sh -c "file -i '{}' | grep -q 'x-executable; charset=binary'" \; -print 2> /dev/null
}

make_launch_files_for_binary()
{
    local launchDirName=launches
    local buildOutputDir=
    local theBinary=
    local defaultArgs=
    unset defaultWorkingDir

    while [[ "${1#-}" != "$1" ]]; do
        curarg="$1"
        shift
        case $curarg in
            -buildOutputDir)
                buildOutputDir="$1"
                shift
                ;;
            -launchDirName)
                launchDirName="$1"
                shift
                ;;
            -binary)
                theBinary="$1"
                shift
                ;;
            -defaultWorkingDir)
                local defaultWorkingDir="$1"
                shift
                ;;
            -defaultArgs)
                defaultArgs="$*"
                # Stop processing we absorbed all arguments
                break
                ;;
            *)
                exit_with_error "$FUNCNAME: Unrecognized option '$curarg'."
                ;;
        esac
    done
    
    if [[ -z "${buildOutputDir}" ]]; then
        exit_with_error "$FUNCNAME: Must supply a build output directory."
    elif [[ ! -d "$SUBPROJECTDIR/${buildOutputDir}" ]]; then
        exit_with_error "$FUNCNAME: Build output directory" \
            "'$SUBPROJECTDIR/${buildOutputDir}' does not exist."
    fi
    
    if [[ -z "${theBinary}" ]]; then
        exit_with_error "$FUNCNAME: Must supply a binary."
    elif [[ ! -e "$SUBPROJECTDIR/${buildOutputDir}/${theBinary#./}" ]]; then
        exit_with_error "$FUNCNAME: Binary" \
            "'$SUBPROJECTDIR/${buildOutputDir}/${theBinary#./}' does not exist."
    fi
    
    # Strip off leading ./
    theBinary=${theBinary#./}
    
    trace_off
    local binaryDirName="$(dirname "$theBinary")"
    export MAINBINARY="$(basename "$theBinary")"
    export MAINBINSUBDIR="${buildOutputDir}/$binaryDirName"
    
    # try to simplify the relative path in case there are relative path (../ or ./)
    # directories within the path.  If they can be eliminated, they will. 
    MAINBINSUBDIR="$(cd ${SUBPROJECTDIR}; simplify_relative_path "$MAINBINSUBDIR")"
    
    # Assume the launches are all the in the same folder as a default.  If there
    # is a relative path from the build output area to the binary itself, we'll
    # mimic that heirarchy in the launch directory parent folder.
    local launchSubDir="${launchDirName}"
    if [[ "${MAINBINSUBDIR}" == "${buildOutputDir}" ]]; then
        : # Binary is directly in the output directory, just use launchSubDir
    elif [[ "${MAINBINSUBDIR#${buildOutputDir}/}" != "${MAINBINSUBDIR}" ]]; then
        launchSubDir="${launchSubDir}/${MAINBINSUBDIR#${buildOutputDir}/}"
    else
        # In some projects, the build and staging area are parallel. In that
        # case, we can try to strip the parent folder instead, otherwise there
        # would be a .. in the path to the launch subdirectory.
        local buildOutputDirParent="${buildOutputDir%/*}"
        if [[ "${MAINBINSUBDIR#${buildOutputDirParent}/}" != "${MAINBINSUBDIR}" ]]; then
            launchSubDir="${launchSubDir}/${MAINBINSUBDIR#${buildOutputDirParent}/}"
        fi
    fi
    export MAINBINLTSUBDIR="${MAINBINSUBDIR}"
    export MAINBINPATH="${buildOutputDir}/${launchSubDir}/${MAINBINARY}"
    export BINLINKS="$MAINBINARY"
    export BINARIES="$MAINBINARY"
    export lt_MAINBINARY="$MAINBINARY"
    shift

    # Set the default arguments and working directory for this binary to
    # put in the launch file (editable by the user in the Run/Debug
    # configuration dialog box). Note: If the build is regenerating a
    # launch file that already exists, the previous user-entered values
    # are used and these variables below are ignored.)
    export LAUNCHFILE_EXECSW="${defaultArgs}"
    # If default working directory is unset use the default (location of binary)
    export LAUNCHFILE_EXECWD="${defaultWorkingDir-${MAINBINLTSUBDIR}}"

    # This location is where we will place the symbolic link to
    # the actual sub project folder 
    local rwssubprojectdir="$RWSDIR/$LOCALPROJECTNAME/$SUBPROJECT"
    # If the sub project is . strip off the trailing /.
    rwssubprojectdir="${rwssubprojectdir%/.}"
    
    # If there is no subproject directory, or if it is older than this
    # script, let's recreate it.
    if [[ "$rwssubprojectdir" -ot "${BASH_SOURCE[0]:-$0}" ]]; then
        if [[ -e "$RWSDIR" ]]; then
            trace_on
            rm -r "$RWSDIR"
            trace_off
        fi
        # Make sure LOCALHDRCACHE has no legacy escaping
        verify_no_legacy_escaped_path_variables
        local hdrcacherelpath="${LOCALHDRCACHE#/}"
        
        # Below we build the path all the way to the symbolic link, but
        # then remove the last part of the path which is either the
        # symbolic link or a temporary folder we created.  Once we remove
        # it we can place the symbolic link in the last step.
        trace_on
        mkdir -p "$rwssubprojectdir" && \
        rm -rf "$rwssubprojectdir" && \
        mkdir -p "$RWSDIR/${hdrcacherelpath%/*}" && \
        ln -s / "$RWSDIR/$hdrcacherelpath" && \
        ln -s $SUBPROJECTDIR "$rwssubprojectdir"
        trace_off
    fi
    prepare-binary-for-remote-gdb.sh
}

get_core_dump_temp_location()
{
    local varname=$1
    if [[ -z "$varname" ]]; then
        exit_with_error "$FUNCNAME: Must supply variable name."
    fi

    local _result=/var/tmp

    eval "$varname='${_result}'"
}

get_script_shell()
{
    # Grab the line at the top
    local shellLine="$(head -n 1 "${1}" | grep "^#\!" )"

    # Strip out just the file part of the shell line
    local shell="$(echo "${shellLine}" | sed "s@^#\![ ]*\([/a-z]*\).*@\1@")"

    echo "${shell}"
}

get_script_shell_type()
{
    local shell="$(get_script_shell ${1})"

    # And then strip just to the name of the shell
    local shellType="${shell##*/}"
    if [[ "${shellType}" == "tcsh" ]]; then
        shellType=csh
    elif [[ "${shellType}" == "sh" ]]; then
        shellType=bash
    fi
    echo "${shellType}"
}

source_script()
{
    # Source a script, written in another language, and import certain
    # variables

    local exportedVars=
    if [[ "$1" != "${1##-vars=}" ]]; then
        local exportedVars="${1##-vars=}"
        shift

        # Convert all the colon separators to spaces
        exportedVars=${exportedVars//:/ }
    fi
    local script="$1"
    shift

    if [[ ! -e "$script" ]]; then
        wait_then_exit_with_error "Cannot find $script..."
    fi

    local scriptType="$(get_script_shell_type "$script")"

    if [[ "${scriptType}" == "bash" ]]; then
        # It is a bash or sh script, so we can just source it.
        source "$script" "$@"
    elif [[ "${scriptType}" == "csh" ]]; then
        # We have a csh or tcsh script, so we can't source it directly,
        # but we can scan it for variables it sets, run it with csh or tcsh
        # and then create a bunch of export statements for the variables it
        # ends up setting.

        # The xx variable is the marker on output lines that indicates it is
        # an export statement.  When we write that out, we know it is not to
        # be written to stdout, but rather used to create the list of export
        # statements to evaluate.
        local xx="_export@"

        local sc=""
        sc="$sc; source ${script} $*"
        # Look through the script and get a list of all variables used
        # with setenv.  This list is
        detectedVars="$(cat ${script} | tr '\t' ' ' | grep "setenv " | \
                sed "s#[ ]*setenv[ ]\([_A-Za-z][_A-Za-z0-9]*\)[ ].*#\1#" | \
                sort -u | xargs)"
        debug_echo "detectedVars are [$detectedVars]"
        exportedVars="$(echo ${exportedVars} ${detectedVars} | \
                xargs -n1 | sort -u | xargs)"
        debug_echo "exportedVars are [$exportedVars]"

        local varname
        for varname in $exportedVars; do
            sc="$sc; if (\$?$varname) eval 'echo $xx $varname=\$$varname;'"
        done
        sc="${sc:2}"

        # Let's get the full path of the shell we'll execute
        local scriptShell="$(get_script_shell "${script}")"

        # Let's run it, and store the output in an environment variable.  It
        # will have mixed in with it any export statements we want to use.
        local output="$($scriptShell -c "$sc")"

        # Write out the standard output without the exported statements
        echo "${output}" | grep -v "^$xx"

        # Now extract all the lines with the signal and export those variables
        local env="$(echo "${output}" | grep "^$xx" | sed "s#$xx#export#")"

        # Finally evaluate the list of export statements.  We have now
        # "fake-sourced" the csh script!  Good enough for backwards
        # compatability.
        eval "${env}"
    else
        wait_then_exit_with_error "Unsupported script type ${scriptType} ..."
    fi
}

wipe_packages_in_dir()
{
    local dir=$1
    if [[ -z "$dir" ]]; then
        exit_with_error "$FUNCNAME: Must supply a directory."
    fi
    if [[ ! -d "$dir" ]]; then
        exit_with_error "$FUNCNAME: Directory '$dir' does not exist."
    fi

    # Do wipe
    echo > $dir/foo.tgz
    echo > $dir/foo.tbz
    echo > $dir/foo.tqz
    echo > $dir/pkg-tmpplist
    rm $dir/pkg-tmpplist $dir/*.tgz $dir/*.tbz $dir/*.tqz
}

# Get the md5 hash of a file
get_md5()
{
    if [[ -e /sbin/md5 ]]; then
        /sbin/md5 -q "$@"
    else
        md5sum "$@" | sed 's/\([0-9a-f]*\) .*/\1/'
    fi
}

wrap_default_compiler_for_absolute_path()
{
    # This command enables wrapping of compilers to use absolute paths
    # to the source's file name by adding the wrapped compilers to the
    # path.  Poor cd/pushd/popd discovery makes this necessary, but
    # nowadays this is probably not needed.
    export PATH="$BINDEV/wrapped_compilers:$PATH"
}

if [[ "$OSTYPE" == "cygwin" ]]; then
    get_vcvars32_bat()
    {
        local varname=$1
        if [[ -z "$varname" ]]; then
            exit_with_error "$FUNCNAME: Must supply variable name."
        fi

        local _result=$(cygpath "$(set | grep "COMNTOOLS=" | \
        sed "s#VS.*COMNTOOLS='\\(.*\\)Common7\\\\Tools\\\\'#\\1VC\\\\bin\\\\vcvars32.bat#" | \
        grep "vcvars32\\.bat\$" | tail -n 1)")
        eval "$varname='${_result}'"
    }
    
    cmake()
    {
        trace_off
        local args="cmake.exe"
        while [[ -n "$1" ]]; do
            local arg="$1"
            shift
            case $arg in
                *=*)
                    local key="${arg%%=*}"
                    local value="${arg#*=}"
                    case $value in
                        /cygdrive/*|[A-Za-z]:\\*)
                            value="$(cygpath -w "$value")"
                            value="${value//\\/\/}"
                            ;;
                        *\\*)
                            value="${value//\\/\/}"
                            ;;
                    esac
                    arg="$key='$value'"
                    ;;
                *)
                    arg="'$arg'"
                    ;;
            esac
            args="$args $arg"
        done
        eval "$args"
        trace_on
    }
    
    make()
    {
        trace_off
        local VSXXVCVARS32BAT=
        get_vcvars32_bat VSXXVCVARS32BAT
        local config=""
        local configOpts=""
        if [[ -e CMakeCache.txt ]]; then
            config=$(grep CMAKE_BUILD_TYPE CMakeCache.txt | sed "s#^.*=##")
        fi
        if [[ -n "$config" ]]; then
            configOpts="/p:Configuration=$config"
        fi
        local target=
        
        # Consume any leading -j<n> or -j <n> parameter
        if [[ "$1" == "-j" ]]; then
            shift 2
        elif [[ "${1#-j}" != "${1}" ]]; then
            shift 1
        fi
        
        local _ctest_cmd=""
        if [[ "$1" == "test" ]]; then
            shift
            local test_args="$*"
            local ctest_args=""
            if [[ "${test_args}" != "${test_args#ARGS=}" ]]; then
                local ctest_args=""
                eval "ctest_args='${test_args#ARGS=}'"
                _ctest_cmd="echo 'Yep!' '${ctest_args}'"
            fi
            if [[ -z "${ctest_args}" ]] || [[ "${ctest_args}" == "-V" ]]; then
                target=RUN_TESTS.vcxproj
            else
                target=
                _ctest_cmd="ctest -C $config ${ctest_args}"
            fi
            # To get detailed output on unit test failures.
            export CTEST_OUTPUT_ON_FAILURE=1
        elif [[ "$1" == "install" ]]; then
            target=INSTALL.vcxproj
        else
            target=ALL_BUILD.vcxproj
        fi
        local verbosity=normal
        # Fixing the location of the TEMP directory to avoid MSB8029 warnings.
        export TEMP="/var/tmp"
        export TMP="$TEMP"
        
        # Strip all of cygwin from the path so that cp, ls and other unix
        # commands won't be in the path
        local newPath="$(echo "$PATH" | tr ':' '\n' | \
            egrep -v "^/usr/bin|^/usr/local/bin|^/bin" | tr '\n' ':')"
        
        if [[ -n "$target" ]]; then
            local _cmd="\"$VSXXVCVARS32BAT\" \& msbuild /fl /m $configOpts"
            _cmd="${_cmd} /p:GenerateFullPaths=True /p:BuildInParallel=true /nologo"
            _cmd="${_cmd} /v:$verbosity /clp:ShowCommandLine,DisableConsoleColor $target"
        else
            _cmd="${_ctest_cmd}"
        fi

        # Before turning on trace, show the command we are about to run
        echo ${_cmd}

        # Change the PATH only for executing msbuild
        PATH="$newPath" eval "${_cmd}"
        trace_on
    }
fi
export_all_functions