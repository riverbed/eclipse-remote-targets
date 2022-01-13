#! /bin/bash
#
# key-setup.sh -- steps a user through setting up his or her private keys
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#


# Header files
source common-functions.sh

get_compiler_headers_bash_command()
{
    local varname=$1
    if [[ -z "$varname" ]]; then
        exit_with_error "Must supply output variable name."
    fi
    local compiler="$2"
    if [[ -z "$compiler" ]]; then
        exit_with_error "Must supply compiler."
    fi
    shift 2

    local specsFile=
    case $compiler in
        *++)
            specsFile="/tmp/specs.cpp"
            ;;
        *cc)
            specsFile="/tmp/specs.c"
            ;;
        *)
            exit_with_error "Unknown compiler type."
            ;;
    esac

    local _result=""
    _result="${_result}\$(echo > ${specsFile}"
    _result="${_result} && ${compiler} -E -P -v -dD ${specsFile}"
    _result="${_result} 2>&1 >/dev/null |"
    _result="${_result} sed -n \"s#^ \\\\(/.*\\\\).*#\\\\1#p\" |"
    _result="${_result} grep -v -e -dD | xargs |"
    _result="${_result} sed \"s# #:#g\" && rm ${specsFile})"

    eval "$varname='${_result}'"
}

get_compiler_version_command()
{
    local varname=$1
    if [[ -z "$varname" ]]; then
        exit_with_error "Must supply output variable name."
    fi
    local compiler="$2"
    if [[ -z "$compiler" ]]; then
        exit_with_error "Must supply compiler."
    fi
    shift 2

    local compilerLabel=
    case $compiler in
        *g++)
            compilerLabel="g++"
            ;;
        *gcc)
            compilerLabel="gcc"
            ;;
        *)
            compilerLabel="${compiler##*/}"
            ;;
    esac

    local _result=""
    _result="${_result}{ ${compiler} --version 2>&- || echo 0.0.0; } |"
    _result="${_result} head -n 1 |"
    _result="${_result} sed \"s#.*\\([0-9][0-9]*\\)\\."
    _result="${_result}\\([0-9][0-9]*\\)\\."
    _result="${_result}\\([0-9x][0-9x]*\\).*"
    _result="${_result}#${compilerLabel}\\1\\2\\3#\""

    eval "$varname='${_result}'"
}

remove_subfolders_and_duplicates_of_path_list()
{
    local out_varname=$1
    if [[ -z "${out_varname}" ]]; then
        exit_with_error "Must supply output variable name."
    fi
    local input_include_headers="$2"
    if [[ -z "$input_include_headers" ]]; then
        exit_with_error "Must supply input include headers name."
    fi
    shift 2

    # Get rid of leading or extra colons, and remove duplicates
    local unique_include_headers=$(echo ${input_include_headers} | \
        tr ':' '\n' | sort -u | tr '\n' ':')

    # We now need to remove entries which are sub-folders of other entries.
    # Since we have a list that is now sorted, we just need to check that
    # each subsequent item doesn't have a parent folder before it.

    local _result=""
    local prev_folder=""
    IFS=":"
    for current_folder in ${unique_include_headers}; do
        # If the current folder is NOT a sub-folder of the last known parent
        local current_parent=${current_folder%/*}/
        if [[ "${current_parent#${prev_folder}}" == "${current_parent}" ]]; then
            # Append this entry, and consider the current folder as the next
            # possible parent.  There will be no more parents of the previous
            # value of prev_folder.
            _result="${_result}${_result:+:}${current_folder}"
            prev_folder="${current_folder}"
        fi
    done
    unset IFS

    eval "${out_varname}='${_result}'"
}

remove_known_host()
{
    local known_host=$1
    # Get only the first part of the known host name, in case the
    # same host is in the file as a fully-qualified domain name and
    # just a partial name
    local known_host_base=${known_host%%.*}
    local known_hosts_file="$HOME/.ssh/known_hosts"
    local new_known_hosts_file="${known_hosts_file}.new"
        
    if [[ -z "${known_host_base}" ]]; then
        exit_with_error "Must supply known host name."
    fi
    if [[ ! -e "${known_hosts_file}" ]]; then
        return
    fi
    
    # Remove the known host from the known hosts file if present:
    # Note: by using the base part of the host name, we can match
    # against all variants of the host name:
    # i.e., "machine.domain.com" and also "machine"
    grep -i -v "^${known_host_base/./\\.}[., ]" "${known_hosts_file}" > "${new_known_hosts_file}"
    mv "${new_known_hosts_file}" "${known_hosts_file}"
}

key_setup_main()
{
    # =================================================================
    # Doing basic set up of remote system to make sure logging in works
    # =================================================================

    if [[ ! -d "$HOME/.ssh" ]]; then
        echo "No \"$HOME/.ssh\" directory found.  Creating it now..."
        mkdir "$HOME/.ssh"
        echo
    fi

    if [[ ! -e "$HOME/.ssh/id_rsa" ]]; then
        echo "No private key available.  Creating one now."
        echo
        echo "NOTE: Simply hit enter below, accepting the default location."
        echo
        ssh-keygen -t rsa -N ''
        echo
        echo
        echo
        echo
    fi

    if [[ ! -e "$HOME/.ssh/id_rsa" ]]; then
        echo "Failed to create an openssh format private key."
        pause
        exit
    fi

    source makePlatformPrivateKey.sh
    if [[ $? != 0 ]]; then
        exit
    fi

    if [[ ! -e "$HOME/.ssh/id_rsa.pub" ]]; then
        echo "Failed to create an openssh format public key."
        pause
        exit
    fi

    # Use key itself, replacing keys problematic for sed with .
    keylabel="$(cat "$HOME/.ssh/id_rsa.pub" | tr " " "\n" | tail -n 2 | head -n 1)"
    keylabel="${keylabel//=/[=]}"
    keylabel="${keylabel//+/[+]}"

    pubkey="$(< "$HOME/.ssh/id_rsa.pub")"

    # echo public key is [$pubkey]

    rsynctestfile="$HOME/.ssh/test.txt"
    privatekeyfile="$HOME/.ssh/id_rsa"
    publickeyfile="$HOME/.ssh/id_rsa.pub"

    echo
    echo "Testing keys for $buildusr on $buildhst..."

    s_c="mkdir -p .ssh"
    s_c="$s_c;  echo REMOVEME >> .ssh/authorized_keys"
    s_c="$s_c;  cat .ssh/authorized_keys"
    s_c="$s_c | sed s@$keylabel@REMOVEME@g"
    s_c="$s_c | grep -v REMOVEME > .ssh/authorized_keys.tmp"
    s_c="$s_c;  echo $pubkey >> .ssh/authorized_keys.tmp"
    s_c="$s_c;  rm .ssh/authorized_keys"
    s_c="$s_c;  mv .ssh/authorized_keys.tmp .ssh/authorized_keys"
    s_c="$s_c;  chmod 644 .ssh/authorized_keys"
    s_c="$s_c;  echo $buildhst ssh test successful."
    
    # Sometimes the host is re-imaged: this makes sure we don't do
    # checks on known hosts for build machines.
    # remove_known_host $buildhst

    ssh "$buildusr@$buildhst" "$s_c"
    local result="$?"

    if [[ "$result" != "0" ]]; then
        remove_known_host $buildhst
        # Sometimes the host is re-imaged: this makes sure we don't do
        # checks on known hosts for build machines.

        ssh "$buildusr@$buildhst" "$s_c"
        result="$?"
    fi

    if [[ "$result" != "0" ]]; then
        echo "$buildhst ssh test failed."
        pause
        exit
    fi

    # Make sure INDEXER_CXX_COMPILER and INDEXER_C_COMPILER have
    # no legacy escaping
    verify_no_legacy_escaped_path_variables
    
    # Get the compiler used by the indexer
    cxx_compiler="${INDEXER_CXX_COMPILER}"
    # If no cxx_compiler was specified, use g++
    cxx_compiler="${cxx_compiler:-g++}"

    # Get the compiler used by the indexer
    c_compiler="${INDEXER_C_COMPILER}"
    # If no c_compiler was specified, use gcc
    c_compiler="${c_compiler:-gcc}"

    # This command gets the include paths on the remote machine.
    local c_comp_cmd
    get_compiler_headers_bash_command cxx_comp_cmd "${cxx_compiler}"
    get_compiler_headers_bash_command   c_comp_cmd "${c_compiler}"
    get_compiler_version_command c_ver_cmd "${c_compiler}"
    local vc_ver_cmd="eval \$(set | grep COMNTOOLS= | sed s/VS.\*COMNTOOLS=/VSXXCOMNTOOLS=/ | tail -n 1)"
    vc_ver_cmd="${vc_ver_cmd}; { cmd /c \"\$VSXXCOMNTOOLS/../../VC/bin/vcvars32.bat\""
    vc_ver_cmd="${vc_ver_cmd} \\& set VisualStudioVersion 2> /dev/null || echo N/A"
    vc_ver_cmd="${vc_ver_cmd}; } | sed s/^VisualStudioVersion=//"

    local vc_inc_cmd="\$(cygpath -p \"\$(eval \$(set | grep COMNTOOLS= | sed s/VS.\*COMNTOOLS=/VSXXCOMNTOOLS=/ | tail -n 1)"
    vc_inc_cmd="${vc_inc_cmd}; { cmd /c \"\$VSXXCOMNTOOLS/../../VC/bin/vcvars32.bat\""
    vc_inc_cmd="${vc_inc_cmd} \\& set INCLUDE 2> /dev/null || echo"
    vc_inc_cmd="${vc_inc_cmd}; } | sed s/^INCLUDE=//)\" 2> /dev/null || echo)"

    # Let's start with the default lists from the shell expansion command that
    # interrogates the compiler for their default headers.  We do this for both
    # the gcc and g++ compilers, understanding there will be overlap.  We then
    # add in any explicit header path locations manually passed in via the
    # configuration variable HEADER_LOCATIONS.  Since that list is : separated,
    # we convert the separator to spaces.
    local header_paths="${cxx_comp_cmd}:${c_comp_cmd}:${vc_inc_cmd}${HEADER_LOCATIONS:+:}${HEADER_LOCATIONS}"
    local source_paths="${header_paths}${DEBUG_SOURCE_LOCATIONS:+:}${DEBUG_SOURCE_LOCATIONS}"

    s_c="echo -n \"RMVZZ=\"&& uname -r"
    s_c="$s_c;  bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }echo -n INCZZ=; path_list=\"$source_paths\";"
    s_c="$s_c       IFS=\":\"; for path_item in "\$path_list"; do"
    s_c="$s_c         [[ -z \"\$path_item\" ]] && continue;"
    # Get both the canonical and literal item
    s_c="$s_c         echo -n \":\$(cd \"\$path_item\" >& /dev/null && pwd)\";"
    s_c="$s_c         echo -n \":\$(cd \"\$path_item\" >& /dev/null && pwd -P)\";"
    s_c="$s_c       done; unset IFS; echo'"
    s_c="$s_c;  echo OSTZZ=\$OSTYPE"
    s_c="$s_c;  echo HSTZZ=\$HOSTTYPE"
    s_c="$s_c;  bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }echo -n \"CVRZZ=\"&& $c_ver_cmd'"
    s_c="$s_c;  bash -c 'echo -n \"VCVZZ=\"&& $vc_ver_cmd'"
    s_c="$s_c;  echo -n \"HNMZZ=\"&& hostname -s"
    s_c="$s_c;  mkdir -p $buildhme/.remoteEclipse/bindev && cd $buildhme"
    s_c="$s_c      && echo -n \"HFPZZ=\"&& bash -c '${REMOTE_PRE_EXEC}${REMOTE_PRE_EXEC:+; }pwd -P'"

    # sniemczyk: 2014-11-11: Forcing use of REMOTE_BASH for the last step to
    # make sure to Report an error if a box does not have bash.

    local outfile="$TMPDIR/pid$$-keytest.txt"
    rm -f "$outfile"

    ssh "$buildusr@$buildhst" "$s_c" | \
            tee "$outfile" | sed $LINEBUFSEDSWITCH -n '/ZZ=/!p'
    result="${PIPESTATUS[0]}"

    buildhfp=
    remoterv=
    remoteih=
    remoteos=
    remoteht=
    remotehn=
    remotecv=
    remotevv=
    if [[ -e "$outfile" ]]; then
        buildhfp="$(grep HFPZZ= "$outfile" | sed "s#HFPZZ=##g")"
        remoterv="$(grep RMVZZ= "$outfile" | sed "s#RMVZZ=##g")"
        remoteih="$(grep INCZZ= "$outfile" | sed "s#INCZZ=##g")"
        remoteos="$(grep OSTZZ= "$outfile" | sed "s#OSTZZ=##g")"
        remoteht="$(grep HSTZZ= "$outfile" | sed "s#HSTZZ=##g")"
        remotehn="$(grep HNMZZ= "$outfile" | sed "s#HNMZZ=##g")"
        remotecv="$(grep CVRZZ= "$outfile" | sed "s#CVRZZ=##g")"
        remotevv="$(grep VCVZZ= "$outfile" | sed "s#VCVZZ=##g")"

        if    [[ "$remoteos" == "cygwin" ]] && \
              [[ "${remotecv}" != "${remotecv%000}" ]]; then
            remotecv=no${remotecv%000}
            if   [[ "${remotevv}" != "N/A" ]] && \
                 [[ -n "${remotevv}" ]]; then
                remotecv="vc${remotevv//./}"
                INDEXER_CXX_COMPILER="cygwin_vcpp.sh"
                INDEXER_C_COMPILER="cygwin_vcc.sh"
            fi
        fi

        remove_subfolders_and_duplicates_of_path_list remoteih "$remoteih"
    fi

    rm -f "$outfile"

    if [[ "$result" == "0" ]]; then
        echo Testing rsync for $buildusr on $buildhst ...
        if [[ -e "$rsynctestfile" ]]; then
            rm -f "$rsynctestfile"
        fi
        rsync -q -av "$buildusr@$buildhst:.ssh/authorized_keys" "$rsynctestfile"
        if [[ -e "$rsynctestfile" ]]; then
            echo Rsync test on $buildhst succeeded.
            rm -f "$rsynctestfile"
            rsync -q -av --chmod=g-rwx,o-rwx "$privatekeyfile" \
                "$buildusr@$buildhst:.ssh/id_rsa" && \
            rsync -q -av --chmod=g-wx,o-wx "$publickeyfile" \
                "$buildusr@$buildhst:.ssh/id_rsa.pub"
        else
            echo "Rsync test on $buildhst failed."
            pause
            exit
        fi
    else
        echo "$buildhst ssh test failed."
        pause
        exit
    fi
    echo

    if [[ "$deployhst" == "none" ]]; then
        return;
    fi

    dprompt="Install key on $deployhst?"
    dprompt="$dprompt (1st time requires the password for $deployusr) [yes]: "
    read -p "$dprompt" dodeploykeys
    if [[ -z "$dodeploykeys" ]]; then
        dodeploykeys=yes
    fi

    if [[ "${dodeploykeys:0:1}" == "y" ]] || \
       [[ "${dodeploykeys:0:1}" == "Y" ]]; then
        if [[ -e "$rsynctestfile" ]]; then
            rm -f "$rsynctestfile"
        fi
        s_c="mkdir -p .ssh"
        s_c="$s_c;  echo REMOVEME >> .ssh/authorized_keys"
        s_c="$s_c;  cat .ssh/authorized_keys"
        s_c="$s_c | sed s@$keylabel@REMOVEME@g"
        s_c="$s_c | grep -v REMOVEME > .ssh/authorized_keys.tmp"
        s_c="$s_c;  echo $pubkey >> .ssh/authorized_keys.tmp"
        s_c="$s_c;  rm .ssh/authorized_keys"
        s_c="$s_c;  mv .ssh/authorized_keys.tmp .ssh/authorized_keys"
        s_c="$s_c;  chmod 644 .ssh/authorized_keys"
        s_c="$s_c;  echo $deployhst ssh test successful."

        ssh "$deployusr@$deployhst" "$s_c"
        if [[ "$?" == "0" ]]; then
            scp -q "$deployusr@$deployhst:.ssh/authorized_keys" "$rsynctestfile"
            if [[ -e "$rsynctestfile" ]]; then
                echo "scp+ssh test on $deployhst succeeded."
                rm -f "$rsynctestfile"
                echo "Attempting to connect to $deployhst via $buildhst ..."
                # sniemczyk: 2012-8-1: Because appliances keep changing their
                # key, let's remove the deploy host from the list of known
                # hosts on the build host and do a silent ssh to the box before
                # the real test ssh echo so that we can quietly fix any
                # known_hosts conflict.  We are defeating the man-in-the-middle
                # ssh test this way, but for appliances the clean output and
                # efficiency trumps security.
                s_c="grep -v $deployhst .ssh/known_hosts > .ssh/known_hosts.new"
                s_c="$s_c; mv .ssh/known_hosts.new .ssh/known_hosts"
                s_c="$s_c; ssh $deployusr@$deployhst echo. >& /dev/null"
                s_c="$s_c; ssh $deployusr@$deployhst echo Connection to"
                s_c="$s_c $deployhst via $buildhst test successful."
                ssh "$buildusr@$buildhst" "$s_c"
            else
                echo "scp+ssh test on $deployhst failed."
                pause
                exit
            fi
        else
            echo "$deployhst scp+ssh test failed."
            pause
            exit
        fi
    fi
}

key_setup_main "$@"