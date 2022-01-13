#! /bin/bash
#
# local-remote-common-aliases.sh -- Common functions shared across scripts
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

shopt -s expand_aliases
alias trace_on='{ _pts=$?; PS4=; set -x; setErrorStatus ${_pts}; } 2>/dev/null'
alias trace_restore='{ _pts=$?; PS4=; [[ "${trace_save_flags/x/}" != "${trace_save_flags}" ]] && set -x; setErrorStatus ${_pts}; } 2>/dev/null'
alias trace_off='{ _pts=$?; trace_save_flags="$-"; set +x; setErrorStatus ${_pts}; } 2>/dev/null'
alias sed_unbuf='sed $LINEBUFSEDSWITCH'
