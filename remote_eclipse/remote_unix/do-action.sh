#! /bin/bash
# do-action.sh
#
# This script is the current entry-point for all build or execute commands
# when called from the local Eclipse workspace.
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

#include common functions
source common-remote-functions.sh

enable_build()
{
    dobuild=true
}

enable_clean()
{
    doclean=true
}

enable_retest()
{
    retest=true
    enable_test "$@"
}

enable_test()
{
    dotest=true
    if [ "$dosubtest" == "false" ]; then
        dosubtest="$1"
    fi
}

enable_package()
{
    # Always do a build before building the package.
    enable_build "$@"
    buildpackage=true
}

enable_wipepackage()
{
    wipepackage=true
}

illegal_argument()
{
    local curarg=$1
    echo "Unrecognized argument \"$curarg\" ..." 1>&2
    exit 1
}

do_action_main()
{
    local project=$1
    shift

    export dobuild=false
    export doclean=false
    export dotest=false
    export retest=false
    export buildpackage=false
    export wipepackage=false
    export dosubtest=false
    # Used in eclipse-error-filter.sh
    export SUBPROJECT=$project

    if [ "$1" == "get-compiler-specs" ]; then
        shift
        eclipse-error-filter.sh get-compiler-specs.sh $*
        exit $?
    fi

    while [[ "$1" != "${1#-}"       ]] || \
          [[ "$1" == "build"        ]] || \
          [[ "$1" == "clean"        ]] || \
          [[ "$1" == "exec"         ]] || \
          [[ "$1" == "test"         ]] || \
          [[ "$1" == "retest"       ]] || \
          [[ "$1" == "package"      ]] || \
          [[ "$1" == "buildpackage" ]]; do
        local curarg=$1
        shift
        case "$curarg" in
            -build|build)
                enable_build "$@"
                ;;
            -clean|clean)
                enable_clean "$@"
                ;;
            -package|package|-buildpackage|buildpackage)
                enable_package "$@"
                ;;
            -retest|retest)
                enable_retest "$@"
                ;;
            -test|test)
                enable_test "$@"
                ;;
            -wipepackage)
                enable_wipepackage "$@"
                ;;
            *)
                illegal_argument "$curarg" "$@"
                ;;
        esac
    done

    export LIBTOOLVER=norelink

    # Does the OSTYPE match the pattern linux*?
    if [ "${OSTYPE#linux}" != "${OSTYPE}" ]; then
        LIBTOOLVER=relink
    fi

    export buildActionLabel=build

    if [[ $dotest == true ]]; then
        buildActionLabel="build and test"
    fi

    if [[ $doclean == true ]]; then
        buildActionLabel="clean $buildActionLabel"
    fi

    if [[ -n "$@" ]]; then
        buildActionLabel="$buildActionLabel $@"
    fi

    # All actions to this script are build-related, so we always
    # use the error filter.
    eclipse-error-filter.sh do-action-internal.sh $project $*
}

do_action_main "$@"