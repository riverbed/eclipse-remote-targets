#! /bin/bash
#
# absPathCompilerWrapper.sh -- Wrap any compiler to compile the source
# using the full local path, not a relative path.  This facilitates
# remote compilation by always showing the full path to the source, so that
# it can be easily mapped to the proper path on the other machine.
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# REQUIRES: REMOTEPROJECTDIR defined in order to wrap.  If not defined, it
# will not wrap

wrapCompiler()
{
    local WRAPPED_COMPILER=$1
    # Remove the wrapped compilers from the path.
    export PATH="${PATH//${BINDEV//\//\\/}\/wrapped_compilers:}"
    shift
    if [[ -n "$REMOTEPROJECTDIR" ]]; then
        local LOCHOME="$(dirname "$REMOTEPROJECTDIR")"
        local ABSHOME="$(cd "$LOCHOME" && pwd -P)"
        local ABSPWD="${PWD/${LOCHOME}/${ABSHOME}}"
        local LOCPWD="${ABSPWD/${ABSHOME}/${LOCHOME}}"
        local ABSLOCDEVPATH="$ABSHOME/$(basename "$REMOTEPROJECTDIR")"
    else
        # With no absolute local dev path, the test below will fail,
        # and the compiler will not be change the source to and absolute path
        local ABSLOCDEVPATH=
    fi

    # Are we in the local developer path?  If so, let's wrap the C/C++ file
    # to use an absolute path.
    if [ "${ABSPWD}" != "${ABSPWD#${ABSLOCDEVPATH}}" ]; then
        local RULE_PRE="s@ \([.a-zA-Z0-9\_][-\.a-zA-Z0-9\_\/]*\."
        local RULE_POST="\) @ $LOCPWD/\1 @g"

        local ALL_RULES=
        ALL_RULES="${ALL_RULES};${RULE_PRE}c${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}cc${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}cxx${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}cpp${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}C${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}CC${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}CXX${RULE_POST}"
        ALL_RULES="${ALL_RULES};${RULE_PRE}CPP${RULE_POST}"

        local rmdotdot="s@/[a-zA-Z0-9\_][-a-zA-Z0-9\_\.]*/\.\./@/@g"

        local args
        args=`echo " $@ " | sed "s@ @  @g" | sed "$ALL_RULES" | \
                            sed "s@  @ @g" | sed "s@/\./@/@g" | \
                            sed "$rmdotdot;$rmdotdot;$rmdotdot;$rmdotdot"`

        exec "${WRAPPED_COMPILER##*/}" $args
    else
        # We are not in the local devel path, so use the compiler unwrapped
        "${WRAPPED_COMPILER##*/}" $@
    fi
    exit $?
}