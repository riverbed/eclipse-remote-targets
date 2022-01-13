#! /bin/bash

# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# Build driver for Remote Eclipse
#
# This script will be called with one of three options:
#
# -setup   Export project defaults and then return
# -local   Called before an action is done
# -remote  Called before a remote build action is done
#
# When invoked for local or remote building, the following variables
# indicate whether build or clean targets were used.  Note, the callbacks
# will be called regardless of whether doclean or dobuild are true, so one
# must check these values since the build or clean will be consumed
#
# doclean=(false|true) true if the clean or clean build target is used.
# dobuild=(false|true) true if the build or clean build target is used.

#include common functions
source local-remote-common.sh # for trace_on, trace_off, build_dispatcher

OUTPUT_ROOT=output
OUTPUT_DIR=output/$ACTIVECONFIG
LAUNCH_DIR_NAME=launches
SOURCE_DIR=../.. #relative to output directory

make_all_launch_files()
{
    trace_off
    local binaryFile
    find_binaries_in_dir . | \
    while read binaryFile; do
        if [[ ${binaryFile/CMakeFiles/} != $binaryFile ]]; then
            # Skip any cmake test binaries
            continue
        fi
        
        # Now place the launches in a subfolder of the output directory 
        make_launch_files_for_binary -buildOutputDir ${OUTPUT_DIR} \
            -binary $binaryFile -launchDirName ${LAUNCH_DIR_NAME}
    done
    trace_on
}

ZzModuleName_eclipse_build_setup()
{
    # These arguments are read before running the setup wizard on the project,
    # and can be used to customize the default settings for the project. 
    enable_debug_release_project
    export BANNER_LABEL="thebinary"
}

ZzModuleName_eclipse_build_variables_and_targets()
{
    add_target -targetPath ZzModuleName -targetName "build"
    add_target -targetPath ZzModuleName -targetName "clean"
    add_target -targetPath ZzModuleName -targetName "clean build"
    add_target -targetPath ZzModuleName -targetName "setup"
}

ZzModuleName_eclipse_build_local()
{
    if [[ $doclean == true ]]; then
        local dir=./${OUTPUT_DIR}
        if [[ "$1" == "all" ]]; then
            dir=./${OUTPUT_ROOT}
        fi
        trace_on
        cd $SUBPROJECTDIR && \
        rm -rf ${dir} && \
        rmdir_only_if_empty ./${OUTPUT_ROOT}
        trace_off
    fi
}

ZzModuleName_eclipse_build_remote()
{
    if [[ $doclean == true ]]; then
        local dir=./${OUTPUT_DIR}
        if [[ $1 == "all" ]]; then
            dir=./${OUTPUT_ROOT}
        fi
        trace_on
        cd $SUBPROJECTDIR && \
        rm -rf ${dir} ${RWSDIR} && \
        rmdir_only_if_empty ./${OUTPUT_ROOT}
        trace_off
    fi
    if [[ $dobuild == true ]]; then
        local opts=
        case $ACTIVECONFIG in
            Debug*)
                opts="$opts -DCMAKE_BUILD_TYPE=Debug"
                ;;
            Release*)
                opts="$opts -DCMAKE_BUILD_TYPE=RelWithDebInfo"
                ;;
        esac

        # Set the OUTPUT_DIR of foundation_lib to be the same as the cmake output dir.
        opts="$opts -DOUTPUT_DIR=$SUBPROJECTDIR/${OUTPUT_DIR}"
        
        # Add any custom options set in C/C++ Build > Environment
        if [[ -n "${CUSTOM_BUILD_OPTS}" ]]; then
            opts="$opts ${CUSTOM_BUILD_OPTS}"
        fi

        trace_on
        cd $SUBPROJECTDIR && \
        mkdir -p ${OUTPUT_DIR} && \
        cd ${OUTPUT_DIR} && \
        cmake $opts ${SOURCE_DIR} && \
        make VERBOSE=1 && \
        make_all_launch_files && \
        cd ${SOURCE_DIR}
        trace_off
    fi
}

ZzModuleName_eclipse_build_get_rsync_exclusion_rule()
{
    # Get the rsync exclusion settings:
    # + /exclude/file/pattern/exception
    # /exclude/file/pattern/*
    # Be sure to put all inclusions (with +) before the exclusions
    local exclusion_rule="
        + /${OUTPUT_DIR}/**/CMakeCache.txt
        + /${OUTPUT_DIR}/CMakeCache.txt
        + /${OUTPUT_DIR}/**/Makefile
        + /${OUTPUT_DIR}/Makefile
        + /${OUTPUT_DIR}/**.cqq
        + /${OUTPUT_DIR}/**.hqq
        + /${OUTPUT_DIR}/**.h
        + /${OUTPUT_DIR}/${LAUNCH_DIR_NAME}/**/*
        + /${OUTPUT_DIR}/${LAUNCH_DIR_NAME}/*
        /${OUTPUT_DIR}/**/CMakeFiles/
        /${OUTPUT_DIR}/CMakeFiles/
        + /${OUTPUT_DIR}/**/
        /${OUTPUT_DIR}/**/*
        /${OUTPUT_DIR}/*
        + /${OUTPUT_DIR}
        /${OUTPUT_ROOT}/*
    "
    echo "${exclusion_rule}"
}

build_dispatcher -prefix ZzModuleName_eclipse_build "$@"