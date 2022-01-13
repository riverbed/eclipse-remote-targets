#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source common-remote-functions.sh

# Script to remotely get the compiler specs

ESC_PROJECT_PATH="${PROJECT_LOC//\\/\/}"

real_path_filter()
{
    # This function removes ./ and ../ in paths to replace them
    # change foo/./bar/blah/../quux ==> foo/bar/quux
    sed_unbuf -e 's|/\./|/|g' -e ':a' -e 's|\.\./\.\./|../..../|g' \
              -e 's|^[^/]*/\.\.\/||' -e 't a' -e 's|/[^/]*/\.\.\/|/|' \
              -e 't a' -e 's|\.\.\.\./|../|g' -e 't a'
}

echo_stderr()
{
    echo "$@" 1>&2;
}

get_remaining_args()
{
    added_paths=
    other_args=
    while [ -n "$1" ]; do
        if [ "x${1#\-I//}" != "x${1}" ]; then
            # arguments of the form -I/<path>
            # will be added without validation
            local new_path="${1#\-I//}"
            # If the path doesn't start with a slash, assume it is folder
            # within the local project
            if [ "${new_path#/}" == "${new_path}" ]; then
                new_path="_~WSLP~_/${new_path}"
            fi
            added_paths="${added_paths} ${new_path}"
        elif [ "x${1#\-U//}" != "x${1}" ]; then
            : #Do nothing, discard the -U//SYMBOL arguments
        elif [ "x${1#\-D//}" != "x${1}" ]; then
            # Treat a -D//SYMBOL as a -DSYMBOL during compiler setting
            other_args="${other_args} -D${1#\-D//}"
        else
            other_args="${other_args} $1"
        fi
        shift
    done
    added_paths="${added_paths:1}"
}

compiler=$1
shift
spec_file=$1
shift

get_remaining_args "$@"

# During the compiler inquiry, make sure the remote folder exists
mkdir -p $REMOTEPROJECTDIR >& /dev/null

pattern=
if [ -n "${added_paths}" ]; then
    pattern=" ${added_paths// /_~_ }_~_"
fi

end_search_list="End of search list."
echo > /tmp/$spec_file
{ $compiler ${other_args} /tmp/$spec_file 2>&1 >&3 | \
  real_path_filter | \
  sed_unbuf "s@\(${end_search_list}\)@${pattern}\1@g" | \
  sed_unbuf -e 's/_~_/\'$'\n/g' | \
  sed_unbuf -e "s@_~WSLP~_@${ESC_PROJECT_PATH}@g" >&2; } 3>&1
status=${PIPESTATUS[0]}
rm /tmp/$spec_file > /dev/null
exit ${status}
