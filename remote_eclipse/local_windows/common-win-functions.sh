#! /bin/bash
#
# common-win-functions.sh -- Common functions shared across Windows bash scripts
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

getOptConvertFilenamesUnixToDos()
{
    OPTIONS=
    until [[ -z "$1" ]]; do
        local value="$1"
        local prevalue=
        if [[ "${1:0:2}" = "--" ]]; then
            tmp=${1:2}               # Strip off leading '--'
            if [[ "$tmp" != "${tmp/=/}" ]]; then # Has = ?
                local parameter=${tmp%%=*} # Extract name.
                value=${tmp##*=}           # Extract value.
                prevalue="--$parameter="
            fi
        fi
        shift
        # In case the argument is a file, convert it to Windows-style
        # If it's not, this won't change anything
        if [[ "${value}" != "${value/@/}" ]]; then
            : # (unless it has an @, like an scp remote location argument)
        else
            convert_filename_to_windows value
        fi

        if [[ "${value}" != "${value/ /}" ]]; then
            # Has spaces? wrap it with quotes
            value="\"${value}\""
        fi
        OPTIONS="$OPTIONS $prevalue${value//\\/\\\\}"
    done
    OPTIONS="${OPTIONS:1}"
}

convert_filename_to_windows()
{
    # REQUIRES: the name of a variable containing a filename, absolute or
    # relative, in MSYS-style unix path
    # EFFECT: Changes the value of that variable to a Windows Style path

    local varname=$1
    local file="$(eval echo \$$varname)"
    if [[ "${file:0:1}" == "/" ]]; then
        # Absolute path, could be with drive or an msys alias
        if [[ "${file:2:1}" == "/" ]]; then
            # Absolute path, with a drive letter (/x/File => X:\File)
            local drive="${file:1:1}:"
            local filepath="${file:2}"
            #Capitalize the drive and change the path to backslashes
            file="$(echo $drive | tr '[a-z]' '[A-Z]')$filepath"
        else
            # A path that is an msys alias (/usr/bin)
            filepath="${file%/*}"
            filename="${file##*/}"
            pushd "$filepath" > /dev/null
            file="$(pwd -W)/$filename"
            popd > /dev/null
        fi
    fi
    # Relative or absolute path, we always reverse the slashes
    file="${file//\//\\}"
    #echo "converting file $(eval echo \$$varname) to $file." 1>&2
    eval "${varname}=\"${file}\""
}

msys_escape_all_path_env_variables()
{
    local getVarsSed="/^getVarsSed=/d;/^BASH=/d;/^HOME=/d;/^OLDPWD=/d;/^PATH=/d"
    getVarsSed="${getVarsSed};/^PWD=/d;/^SHELL=/d;/^TEMP=/d;/^TMP=/d;/^TMPDIR=/d"
    getVarsSed="${getVarsSed};/^[A-Za-z_][A-Za-z0-9_]*=[']\\{0,1\\}[/]/p"
    local varList=$(set | sed -n "$getVarsSed" | \
        sed -e "s/^\\([A-Za-z_][A-Za-z0-9_]*\\)=.*$/\\1/")
    local varname=
    for varname in $varList; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"
        # Protect variable from being altered by msys using a triple-colon which
        # works for both msys 1.x and msys 2.x
        eval "$varname=':::${varvalue}'"
    done
}
msys_unescape_all_path_env_variables()
{
    local getVarsSed="/^[A-Za-z_][A-Za-z0-9_]*=[']\\{0,1\\}:::[/]/p"
    local varList=$(declare | sed -n "$getVarsSed" | \
        sed -e "s/^\\([A-Za-z_][A-Za-z0-9_]*\\)=.*$/\\1/")
    local varname=
    for varname in $varList; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"
        varvalue="${varvalue#:::}"
        eval "$varname='${varvalue}'"
    done
}
