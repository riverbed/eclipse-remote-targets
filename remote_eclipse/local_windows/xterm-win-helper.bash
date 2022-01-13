#! /bin/bash
#
# xterm-win-helper.bash -- helper script to launch an "xterm"
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source common-win-functions.sh 

run_xterm_command()
{
    # We need to unset all the exported functions we created because they will
    # become new functions with capital letters, effectively doubling the size
    # of the environment.  Removing the listed functions here will prevent them
    # from being part of the environment in the shell we are about to launch
    local command=$(list_all_functions | sed 's#^\(.*\)$#unset \1;#' | tr '\n' ' ')
    command="${command%; }"
    if [[ -n "$command" ]]; then
        eval "$command"
    fi
    local title="$1"
    shift
    cmd //c start //wait "$title" bash -c "source common-win-functions.sh; msys_unescape_all_path_env_variables; source bash-config.bash; $@"
}

msys_escape_all_path_env_variables && run_xterm_command "$@"