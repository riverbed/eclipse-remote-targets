#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

cygwin_vc_gcc_emulator_main()
{
    # echo "arguments:" "$@"
    local GCC_COMPILER=$1
    shift
    
    # Create a temporary build output folder, and go there
    local tmpPath=/tmp/gccEm.$$
    mkdir -p $tmpPath
    pushd $tmpPath >& /dev/null
    
    local IN_SRC_FILE=get_vc_default_defines.cpp
    if [[ "${GCC_COMPILER}" == "g++" ]]; then
        local OUT_SRC_FILE=${IN_SRC_FILE%.*}.cpp
    else
        local OUT_SRC_FILE=${IN_SRC_FILE%.*}.c
    fi
    cp "$BINDEV/${IN_SRC_FILE}" ${OUT_SRC_FILE}
    local VSXXVCVARS32BAT=
    get_vcvars32_bat VSXXVCVARS32BAT
    "$VSXXVCVARS32BAT" \& cl /GR /EHsc /Zi /nologo ${OUT_SRC_FILE} | grep "#define"
    local includeDirs="$("$VSXXVCVARS32BAT" \& set INCLUDE | sed "s/^INCLUDE=//")"
    includeDirs="${includeDirs%;}"

    while [[ -n "$1" ]]; do
        local arg="$1"
        shift
        if    [[ "$arg" != "${arg#-D}"   ]] && \
              [[ "$arg" == "${arg#-D//}" ]]; then
            local symbol_value="${arg#-D}"
            local symbol="${symbol_value%=*}"
            # If the symbol is different than symbol value, there is a value
            if [[ "$symbol" != "$symbol_value" ]]; then
                local value="${symbol_value#*=}"
            else
                local value=1
            fi
            echo "#define $symbol $value"
        elif  [[ "$arg" != "${arg#-I}"   ]] && \
              [[ "$arg" == "${arg#-I//}" ]]; then
            local include_path="${arg#-I}"
            # Append the new path to the list of include directories.
            includeDirs="${includeDirs}${includeDirs:+;}${include_path}"
        fi
        done
    echo "#include "..." search starts here:" 1>&2
    echo "#include <...> search starts here:" 1>&2
    includeDirs=$(cygpath -p "$includeDirs")
    echo "$includeDirs" | sed "s#^/# /#" | sed "s#:#: #g" | tr ':' '\n' 1>&2
    echo "End of search list." 1>&2
    
    # Jump out of and clean up the temporary build output folder
    popd >& /dev/null
    rm -rf $tmpPath
}

cygwin_vc_gcc_emulator_main "$@"
