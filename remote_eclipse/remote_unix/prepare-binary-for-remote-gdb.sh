#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

source common-remote-functions.sh

is_binary_a_gtest()
{
    local isGtest
    if ldd $1 |& grep -q "libgtest_main\\."; then
        # If we are linking against libgtest_main, we are a gtest
        isGtest=true
    elif ldd $1 |& grep -q "libgtest\\."; then
        # Do we link against gtest, but make our own main? If so we
        # would check for testing::InitGoogleTest
        if strings $1 | grep -q "testing.*InitGoogleTest"; then
            isGtest=true
        else
            isGtest=false
        fi
    fi
    [[ $isGtest == true ]]
}

prepare_binary_for_remote_gdb_main()
{
    ###################################
    # Saving binary and GDB information
    ###################################

    local INCOMING_CHANGES_MARKER=$SUBPROJECTDIR/$MAINBINPATH/noMoreIncomingChanges

    mkdir -p $SUBPROJECTDIR/$MAINBINPATH

    cd $SUBPROJECTDIR

    if [[ -e $SUBPROJECTDIR/$MAINBINSUBDIR/$MAINBINARY ]]; then
        ##############################################################################
        # Now make symbolic links in the Eclipse output path to the binary we will run
        ##############################################################################
        local FULLSUBPROJECTDIR="$(cd $SUBPROJECTDIR; pwd)"
        pushd $SUBPROJECTDIR/$MAINBINPATH >& /dev/null
        local bintolinkto=$SUBPROJECTDIR/$MAINBINSUBDIR/$lt_MAINBINARY
        local fullbintolinkto=$FULLSUBPROJECTDIR/$MAINBINSUBDIR/$lt_MAINBINARY
        for binlink in $BINLINKS; do
            debug_echo "link points to $(readlink $binlink)."
            debug_echo "actual path is $fullbintolinkto."
            if [[ "$(readlink $binlink)" != "$fullbintolinkto" ]]; then
                rm $binlink >& /dev/null
                debug_echo ln -s $bintolinkto $binlink
                ln -s $bintolinkto $binlink
            fi
        done
        popd >& /dev/null
    fi

    # sniemczyk: 2014-12-14: Removing unnecessary overrides before I am
    # committing to support them (unused today)
    local gdbcommand
    get_remote_gdb_bin gdbcommand

    local curgdbversion="$($gdbcommand --version | head -n 1)"
    local oldgdbversion=
    if [[ -e $MAINBINPATH/gdbverout ]]; then
        oldgdbversion="$(cat $MAINBINPATH/gdbverout | head -n 1)"
    fi

    if [[ "$curgdbversion" != "$oldgdbversion" ]]; then
        debug_echo "$curgdbversion detected..."
        $gdbcommand --version > $MAINBINPATH/gdbverout
    fi

    if [[ -z "$curgdbversion" ]]; then
        exit_with_error "No gdb version detected on this remote machine."
    fi

    # Get the location of this script
    local thisScript=${BASH_SOURCE[0]:-$0}

    cat /dev/null > $MAINBINPATH/gdbinit
    cp $MAINBINPATH/gdbinit $MAINBINPATH/gdbinitattach
    cat $SUBPROJECTDIR/$MAINBINPATH/gdbinit > $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new
    
    local coreTempLoc
    get_core_dump_temp_location coreTempLoc
    # This writes out the gdbinitpm-new file, which contains the path to the core dump
    # The file will likely not exist in this temporary location, but you can make symbolic
    # link there to where the coredump itself is, and it will "just work."
    # Be sure to decompress the core if it is stored on the box in a compressed
    # format, e.g lz4 etc.
    echo exec-file $SUBPROJECTDIR/$MAINBINSUBDIR/$lt_MAINBINARY >> $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new
    echo symbol-file $SUBPROJECTDIR/$MAINBINSUBDIR/$lt_MAINBINARY >> $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new
    echo core $coreTempLoc/$lt_MAINBINARY.core >> $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new
    # Making the launch templates
    if is_binary_a_gtest "$SUBPROJECTDIR/$MAINBINSUBDIR/$lt_MAINBINARY"; then
        instantiate-launch-template.sh -hideDebugFavorite -hideRunFavorite
        instantiate-launch-template.sh -type test -testRunner gtest -suffix " (gtest)"
    else
        instantiate-launch-template.sh
    fi
    # Add an attach launch file, but keep it hidden.
    instantiate-launch-template.sh -type attach -hideDebugFavorite
    
    # Not a favorite, since there may be no core to debug!
    instantiate-launch-template.sh -type postmortem -hideDebugFavorite

    local oldgdbinitpmmd5=EMPTY
    if [[ -e $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm ]]; then
        oldgdbinitpmmd5="$(get_md5 $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm)"
    fi
    local newgdbinitpmmd5="$(get_md5 $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new)"

    if [[ "$newgdbinitpmmd5" == "$oldgdbinitpmmd5" ]]; then
        rm $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new
    else
        mv  $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm-new \
            $SUBPROJECTDIR/$MAINBINPATH/gdbinitpm
    fi

    return 0
}

prepare_binary_for_remote_gdb_main "$@"
