#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

cygwin_vcc_main()
{
    cygwin_vc_gcc_emulator.sh gcc "$@"
}

cygwin_vcc_main "$@"
