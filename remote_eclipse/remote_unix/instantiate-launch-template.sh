#! /bin/bash
#
# instantiate-launch-template.sh -- Create a launch file from a template
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

#include common functions
source common-remote-functions.sh

isRunDebugAttachTestTemplate()
{
    [[ "$templateType" == "exec" ]] || \
    [[ "$templateType" == "test" ]] || \
    [[ "$templateType" == "postmortem" ]] || \
    [[ "$templateType" == "attach" ]]
}

isWindowsPath()
{
    case "${1:0:3}" in
        [A-Za-z]\:\\|\\\\[A-Za-z0-9])
            # Match on Drive letter paths or double backslash paths
            return 0
            ;;
        *)
            # Everything else should be considered a Unix path
            return 1
            ;;
    esac
}

unix_to_dos()
{
    # This puts a carriage return at the end of each line.  Because we
    # are trying to be platform compatible, I am sticking with the BSD sed
    # way of using bash to escape the carriage return
    sed -e 's/$/'$'\r/g'
}

unix2platform()
{
    if [[ -z "$1" ]]; then
        # Used as a pipe, it is effectively cat
        if isWindowsPath "${PROJECT_LOC}"; then
            unix_to_dos
        else
            cat
        fi
    else
        if [[ -e "$1" ]]; then
            if isWindowsPath "${PROJECT_LOC}"; then
                # Let's do a unix to dos conversion on the file.
                mv "$1" "$1.old"
                cat "$1.old" | unix_to_dos > "$1"
                rm -f "$1.old"
            else
                : # Actually, do nothing at all.  Don't even touch the file.

            fi
            echo "$1: done." 1>&2
        else
            echo "unix2platform processing $1 (could not open input file):" \
                 "No such file or directory" 1>&2
            exit 255
        fi
    fi
}

makeRbinLaunchScript()
{
    local targetscriptpath="$1"
    local sourcescriptpath="$2"
    local templatename=rbinlaunchT.sh
    local scriptname=rbinlaunch.sh
    local makecopy=true
    if [[ -e "$targetscriptpath/$scriptname" ]]; then
        local targetmd5="$(get_md5 "$targetscriptpath/$scriptname")"
        local sourcemd5="$(get_md5 "$sourcescriptpath/$templatename")"
        if [[ "$sourcemd5" == "$targetmd5" ]]; then
            makecopy=false
        fi
    fi
    if [[ "$makecopy" == "true" ]]; then
        cp -f "$sourcescriptpath/$templatename" "$targetscriptpath/$scriptname"
    fi
}

exportLaunchVariables()
{
    local launchEnvFile="$1"
    shift

    echo "#Local launch environment script" >  "$launchEnvFile"
    local varname
    for varname in $*; do
        local varvalue="$(eval POSIXLY_CORRECT=1 /bin/echo \$$varname)"
        echo "export $varname='$varvalue'"  >> "$launchEnvFile"
    done
}

makeLaunchEnvScript()
{
    local targetscriptpath="$1"
    local oldScriptFile="$targetscriptpath/launchenv.sh"
    local newScriptFile="$targetscriptpath/launchenv.new"
    local makecopy=true

    # This variable is exported for use by gdb to treat all paths to
    # the remote project directory as canonical.
    local remoteprojectdfp="$(cd "$REMOTEPROJECTDIR"; pwd -P)"

    # If the remote project has a different full (canonical) path then the
    # one specified in the environment variable, translate all canonical paths
    # to the entered one.
    if    [[ -n "$remoteprojectdfp" ]] && \
          [[ "$remoteprojectdfp" != "$REMOTEPROJECTDIR" ]]; then
        search="$remoteprojectdfp/"
        replace="$REMOTEPROJECTDIR/"
        DEBUGGER_PATH_SEDEXP="${DEBUGGER_PATH_SEDEXP}${DEBUGGER_PATH_SEDEXP:+;}s#${search}#${replace}#g"
    fi

    exportLaunchVariables "$newScriptFile" LOCALPROJECTNAME MAINBINPATH \
        MAINBINSUBDIR MAINBINLTSUBDIR MAINBINARY \
        lt_MAINBINARY SUBPROJECT DEBUGGER_PATH_SEDEXP REMOTE_GDB_BIN \
        REMOTE_PRE_EXEC

    if [[ -e "$oldScriptFile" ]]; then
        local oldscriptmd5="$(get_md5 "$oldScriptFile")"
        local newscriptmd5="$(get_md5 "$newScriptFile")"
        if [[ "$newscriptmd5" == "$oldscriptmd5" ]]; then
            makecopy=false
        fi
    fi
    if [[ "$makecopy" == "true" ]]; then
        cp -f "$newScriptFile" "$oldScriptFile"
    fi
    rm -f "$newScriptFile"
}

makeRbinBinaryHereFile()
{
    local mainbinlink="$1"
    local targetHereFilePath="$2"
    local hereFileName=.${mainbinlink}.binhere
    local hereFile="${targetHereFilePath}/${hereFileName}"

    if [[ ! -e "${hereFile}" ]]; then
        echo "here" > "${hereFile}"
    fi
}

instantiate_launch_template_variables()
{
    launchlabel="BinaryName"
    locprojtemplate=LocalProjectName
    tmplremprojdir=ZzRemoteProjectDir
    tmplsubproject=ZzModuleName
    tmplmainbinpath=ZzMainBinPath
    tmplrellaunchfile=ZzLaunchFile
    tmpldebuggerbinary=ZZDebuggerBinary
    tmplmainbinarylink=ZZMainBinary

    ltmpprefix="$launchlabel $locprojtemplate"

    local ESC_PROJECT_PATH="${PROJECT_LOC//\\//}"
    local ESC_WORKSPACE_PATH="${WORKSPACE_LOC//\\//}"
    local ESC_REMOTE_ECLIPSE_PATH="${REMOTE_ECLIPSE_LOC//\\//}"
    
    # This variable is exported for use by gdb to treat all paths to
    # the remote project directory as canonical.
    local remoteprojectdfp="$(cd "$REMOTEPROJECTDIR"; pwd -P)"


    # Make sure LOCALHDRCACHE has no legacy escaping
    verify_no_legacy_escaped_path_variables
    
    local pathmap=""
    pathmap="${pathmap};$RWSDIR/$LOCALPROJECTNAME=>${ESC_PROJECT_PATH}"
    pathmap="${pathmap};$RWSDIR/${LOCALHDRCACHE#/}=>${ESC_REMOTE_ECLIPSE_PATH%/*}/${LOCALHDRCACHE#/}"
    pathmap="${pathmap};$REMOTEPROJECTDIR=>${ESC_PROJECT_PATH}"
    pathmap="${pathmap};${REMOTEPROJECTDIR%/*}=>${ESC_PROJECT_PATH%/*}"
   
    # If the canonical path is different, add that path too. 
    if [[ "$remoteprojectdfp" != "$REMOTEPROJECTDIR" ]]; then
        pathmap="${pathmap};$remoteprojectdfp=>${ESC_PROJECT_PATH}"
        pathmap="${pathmap};${remoteprojectdfp%/*}=>${ESC_PROJECT_PATH%/*}"
    fi
    
    pathmap="${pathmap};/=>${ESC_REMOTE_ECLIPSE_PATH%/*}/${LOCALHDRCACHE#/}"

    # If the variable DEBUGGER_PATH_MAPPING is already set, prepend our mappings
    # here first.
    if [[ -n "${DEBUGGER_PATH_MAPPING}" ]]; then
        pathmap="${pathmap};${DEBUGGER_PATH_MAPPING}"
    fi

    DEBUGGER_PATH_MAPPING="${pathmap#;}"
}

replace_debugger_search_replace_parameters()
{
    # We look for the ending of the path map pattern, and we add our new
    # map entry just before this pattern.  This end pattern occurs only once.
    local endpattern="&amp;lt;/mapping&amp;gt;"

    # Note, we assume there will always be at least one pattern, otherwise this
    # works but we have an unapplied change (the empty map list) that Eclipse
    # will try to remove when you open the launch for the first time.  Since
    # we don't anticipate making launches with an empty mapping list, we leave
    # this as is.
    if [[ -z "$1" ]]; then
        exit_with_error "$FUNCNAME: Must give at least one map entry"
    fi

    pathmap="$1;"

    # Use the presence of a search path to indicate we need to add an entry.
    while [[ -n "${pathmap%%;*}" ]]; do
        local pathmapentry="${pathmap%%;*}"
        local searchpath="${pathmapentry%=>*}"
        local replacepath="${pathmapentry#*=>}"

        local newentry=""
        newentry="${newentry}&amp;lt;mapEntry memento=&amp;quot;&amp;amp;lt;"
        newentry="${newentry}?xml version=&amp;amp;quot;1.0&amp;amp;"
        newentry="${newentry}quot; encoding=&amp;amp;quot;UTF-8&amp;amp;"
        newentry="${newentry}quot; standalone=&amp;amp;quot;no&amp;amp;"
        newentry="${newentry}quot;?&amp;amp;gt;&amp;amp;#13;&amp;amp;#10;&amp;"
        newentry="${newentry}amp;lt;mapEntry backendPath=&amp;amp;quot;"
        newentry="${newentry}${searchpath//\//\\\\}"
        newentry="${newentry}&amp;amp;quot; localPath=&amp;amp;quot;"
        newentry="${newentry}${replacepath//\//\\\\}"
        newentry="${newentry}&amp;amp;quot;/&amp;amp;gt;&amp;amp;#13;&amp;"
        newentry="${newentry}amp;#10;&amp;quot;/&amp;gt;&amp;#13;&amp;#10;"

        # Escape the & otherwise it will replace with our end pattern (bad).
        newentry="${newentry//&/\\&}"

        # Insert the new path mapping entry before the end-pattern.
        sedInPlace "s|\(${endpattern}\)|${newentry}\\1|" "$launchFile"

        # Strip off the current entry and get the rest
        pathmap="${pathmap#*;}"
    done
}

get_options()
{
    fileExt=launch
    templateType=exec
    insuffix=
    outsuffix=
    overrideSuffix=false
    runFavorite=true
    debugFavorite=true
    showBinaryNameInLabel=true
    showBinaryPathInLabel=false
    showConfigNameInLabel=false
    case $ACTIVECONFIG in
        Debug*)
            showConfigNameInLabel=true
            ;;
        Release*)
            showConfigNameInLabel=true
            ;;
        *)
            : # Do nothing
            ;;
    esac
    testRunner=gtest
    while [[ "${1#-}" != "$1" ]]; do
        curarg="$1"
        shift
        case $curarg in
            -hideDebugFav*)
                debugFavorite=false
                ;;
            -hideRunFav*)
                runFavorite=false
                ;;
            -debugFav*)
                debugFavorite=true
                ;;
            -runFav*)
                runFavorite=true
                ;;
            -suffix)
                outsuffix="$1"
                overrideSuffix=true
                shift
                ;;
            -type)
                templateType="$1"
                # Run/Debug/Attach/Test templates stand out better with
                # a parenthesis around the type
                if isRunDebugAttachTestTemplate; then
                    insuffix=" ($templateType)"
                else
                    insuffix=" $templateType"
                fi
                shift
                ;;
            -testRunner)
                testRunner="$1"
                shift
                ;;
            -inactive)
                fileExt=iLaunch
                ;;
            -noConfigName)
                showConfigNameInLabel=false
                ;;
            -showConfigName)
                showConfigNameInLabel=true
                ;;
            -noBinaryPath)
                showBinaryPathInLabel=false
                ;;
            -showBinaryPath)
                showBinaryPathInLabel=true
                ;;
            -noBinaryName)
                showBinaryNameInLabel=false
                ;;
            *)
                exit_with_error "Unrecognized launch option."
                ;;
        esac
    done
    
    # Run/Debug/Attach/Test templates stand out better with
    # a parenthesis around the type
    if [[ $overrideSuffix == false ]]; then
        outsuffix="${insuffix}"
    fi

    debug_echo "templateType is '$templateType'"
}

instantiate_launch_template_main()
{
    # Don't actually instantiate any templates if projects are old and stale
    # and probably won't support them
    if [[ -z "$LOCALHDRCACHE" ]]; then
        show_info "This project uses the old standard include setup." \
            "Re-run the project setup script to add support for the new" \
            "launch templates."
        return 0
    fi

    get_options "$@"

    instantiate_launch_template_variables

    local binarySuffix=""
    if [[ $showBinaryNameInLabel == true ]]; then
        if [[ $showBinaryPathInLabel == true ]]; then
            # Note, thie slash is being substituted with a unicode division slash
            # Thus the filename has a slash in it where X's are below...
            #           ="X${MAINBINSUBDIR//\//X}X${MAINBINARY}"
            binarySuffix="∕${MAINBINSUBDIR//\//∕}∕${MAINBINARY}"
        else
            binarySuffix=" ${MAINBINARY}"
        fi
    fi
    local configSuffix=""
    if [[ $showConfigNameInLabel == true ]]; then
        configSuffix=" [${ACTIVECONFIG}]"
    fi

    templatePath="$BINDEV/templates"
    templateFile="$templatePath/${ltmpprefix}${insuffix}.Tlaunch"
    launchPath="$SUBPROJECTDIR/$MAINBINPATH"
    relLaunchPath="$SUBPROJECT/$MAINBINPATH"
    launchFileName="${LOCALPROJECTNAME}${binarySuffix}${configSuffix}${outsuffix}.${fileExt}"
    launchFile="$launchPath/$launchFileName"
    relLaunchFile="$relLaunchPath/$launchFileName"
    launchBackupFile="${launchFile%.launch}.lbak"
    mkdir -p "$launchPath"
    if [[ -e "$launchFile" ]]; then
        mv "$launchFile" "$launchBackupFile"
    fi
    cp "$templateFile" "$launchFile"


    # DD means Directory Delimiter, PD means Path Delimiter F/R = Find/Replace
    if isWindowsPath "${PROJECT_LOC}"; then
        local DDR="\\\\"
        local PD=";"
        local mainbinlink=$MAINBINARY
        # optionally, could add .exe above
    else
        local DDR="/"
        local PD=":"
        local mainbinlink=$MAINBINARY
    fi

    if isRunDebugAttachTestTemplate; then
        makeRbinLaunchScript "$launchPath" "$templatePath"
        makeLaunchEnvScript "$launchPath"
        makeRbinBinaryHereFile "$mainbinlink" "$launchPath"

        # Eclipse butchers handling of spaces and slashes and treating them
        # as separate arguments or munging them, so I am escaping them:
        # '[_]' => ' ' (space)
        #  '/'  => ':'
        # I will undo this in remote-gdb.sh
        local escRelLaunchFile="${relLaunchFile// /[_]}"
        escRelLaunchFile="${escRelLaunchFile//\//:}"
        sedInPlace "s#$tmplrellaunchfile#${escRelLaunchFile}#" "$launchFile"
        
        # If a platform needs to run bash inside a wrapper to handle signalling
        # we support it via the variable LOCAL_DEBUGGER_WRAPPER
        local debuggerbinary="bash '\${workspace_loc:remote_eclipse/local_os/\${system:OS}/remote-gdb.bash}'"
        if [[ -n "${LOCAL_DEBUGGER_WRAPPER}" ]]; then
            debuggerbinary="${LOCAL_DEBUGGER_WRAPPER} $debuggerbinary"
        fi
        # Escape any double quotes
        debuggerbinary="${debuggerbinary//\"/\\&quot\\;}"
        sedInPlace "s#$tmpldebuggerbinary#$debuggerbinary#" "$launchFile"

        replace_debugger_search_replace_parameters "$DEBUGGER_PATH_MAPPING"

        # If Eclipse uses unix slashes on this platform, replace the path
        # mapping text in the debug launches to use forward slashes as well.
        if ! isWindowsPath "${PROJECT_LOC}"; then
            sedInPlace '/core\.source_locator_memento/s/\\/\//g' \
                "$launchFile"
            sedInPlace 's/&amp\;amp\;#13\;//g;s/&amp\;#13\;//g;s/&#13\;//g' \
                "$launchFile"
        fi

        # If we aren't using Windows, Eclipse can't handle the single quotes
        # to wrap the path to the gdb script.
        if ! isWindowsPath "${REMOTE_ECLIPSE_LOC}"; then
            local sedMatch="\\(bash \\)\\('\\)\\(.*/\\)\\(.*\\)\\(}\\)\\('\\)"
            # OK, we are on Unix, so we need to remove the single quotes
            if [[ "${REMOTE_ECLIPSE_LOC}" == "${REMOTE_ECLIPSE_LOC/ /}" ]]; then
                # Since there's no space in the path, we are safe to remove the
                # single quotes since they aren't needed (remove \2 and \6)
                sedInPlace "s#${sedMatch}#\\1\\3\\4\\5#" "$launchFile"
            else
                # In this case we have a space, so we need to run a script in
                # the PATH environment variable to avoid using an explicit path
                # to the script which was properly set during project setup only
                # for this case: when there are spaces in the path to the repo
                # on Unix. This means we remove all but \1 and \4
                sedInPlace "s#${sedMatch}#\\1\\4#" "$launchFile"
            fi
        fi
    fi

    sedInPlace "s/$locprojtemplate/$LOCALPROJECTNAME/g" \
        "$launchFile"

    sedInPlace "s#$tmplsubproject#$SUBPROJECT#g" \
        "$launchFile"

    sedInPlace "s#$tmplmainbinpath#$MAINBINPATH#g" \
        "$launchFile"

    if isRunDebugAttachTestTemplate; then
        # 2012-7-24: Replace the core file specified in the post-mortem launcher
        # with a file that actually exists, because Eclipse Juno cares.  Using
        # the previous dummy value of ./ is a folder, and since folders cause a
        # dialog box to appear in Juno, better to pick a file that always exists
        if [[ "$templateType" == "postmortem" ]]; then
            local dummycorefile="${REMOTE_ECLIPSE_LOC//\\/\\\\}"
            dummycorefile="${dummycorefile}${DDR}local_common${DDR}.dummycorefile"
            local corepathfind="COREFILE_PATH\" value=\"\./\""
            local corepathrepl="COREFILE_PATH\" value=\"$dummycorefile\""

            sedInPlace "s#$corepathfind#$corepathrepl#" \
                "$launchFile"
        fi

        # Make sure LOCALHDRCACHE has no legacy escaping
        verify_no_legacy_escaped_path_variables
        local hdrcachepath="${LOCALHDRCACHE#/}"

        sedInPlace "s@hdrcachepath@${hdrcachepath//@/\\@}@g" \
            "$launchFile"

        if [[ "$debugFavorite" == "false" ]]; then
            local searchString=org.eclipse.debug.ui.launchGroup.debug
            sedInPlace "/${searchString//./\\.}/d" "$launchFile"
        fi

        # Post-mortem debugs can't be on the run launch group
        if [[ "$templateType" == "postmortem" ]] || [[ "$templateType" == "attach" ]]; then
            runFavorite=false
        else
            if [[ "$runFavorite" == "false" ]]; then
                local searchString=org.eclipse.debug.ui.launchGroup.run
                sedInPlace "/${searchString//./\\.}/d" "$launchFile"
            fi
            
            if [[ "$templateType" == "test" ]]; then
                local searchString=ZzTestRunner
                sedInPlace "s#ZzTestRunner#${testRunner}#" "$launchFile"
            fi
            
            # This is an normal "exec" or "test" launch, so lets replace any environment variables
            set_exec_environment_variables
        fi

        local favGroupMarkerString=ZZfav_
        if   [[ "$runFavorite" == "false"   ]] && \
             [[ "$debugFavorite" == "false" ]]; then
            # if there are no favorite groups, remove both the favorite group
            # list line and the closing tag below.
            sedInPlace "/${favGroupMarkerString}/d" "$launchFile"
        else
            # otherwise, keep the tags but remove the marker pattern.
            sedInPlace "s/${favGroupMarkerString}//" "$launchFile"
        fi

        sedInPlace "s#$tmplremprojdir#$REMOTEPROJECTDIR#g" \
            "$launchFile"

        sedInPlace "s#$tmplmainbinarylink#$mainbinlink#g" \
            "$launchFile"
    fi

    unix2platform "$launchFile" >& /dev/null

    # Move back any templates that have not changed, to prevent unnecessary
    # syncing.
    local oldlaunchmd5=NOTFOUND
    if [[ -e "$launchBackupFile" ]]; then
        oldlaunchmd5="$(get_md5 "$launchBackupFile")"
    fi
    newlaunchmd5="$(get_md5 "$launchFile")"
    debug_echo "For $launchFile, old is $oldlaunchmd5 new is $newlaunchmd5"
    if [[ "$newlaunchmd5" == "$oldlaunchmd5" ]]; then
        debug_echo "Match, moving back."
        mv "$launchBackupFile" "$launchFile"
    else
        rm -f "$launchBackupFile"
    fi

    return
}

set_exec_environment_variables()
{
    # Initially we have the values specified by the build.
    # These will be overwritten if we have a backup below.
    
    # If there were any launchfile environment variables from the backup, use those
    if [[ -e "$launchBackupFile" ]]; then
        # Now get the values from the previous launch, allowing 'stickiness'
        get_launch_file_environment_variables "$launchBackupFile" LAUNCHFILE_
    fi
    
    # If LAUNCHFILE_EXECWD was never defined, use the directory of the binary
    # for legacy libtoolized binaries, run from the directory of the wrapper.
    if [[ ! ${!LAUNCHFILE_EXECWD[@]} ]]; then
        LAUNCHFILE_EXECWD="${MAINBINLTSUBDIR}"
    fi
    
    # If LAUNCHFILE_EXECSW was never defined, define it to be blank so
    # at the launch file has an EXECSW variable users can set.
    if [[ ! ${!LAUNCHFILE_EXECSW[@]} ]]; then
        LAUNCHFILE_EXECSW=""
    fi
    
    set_launch_file_environment_variable "$launchFile" LAUNCHFILE_BINALIAS BINALIAS
    set_launch_file_environment_variable "$launchFile" LAUNCHFILE_EXECSW EXECSW
    set_launch_file_environment_variable "$launchFile" LAUNCHFILE_EXECWD EXECWD
}

instantiate_launch_template_main "$@"
