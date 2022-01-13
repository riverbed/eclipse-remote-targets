#! /bin/bash
#
# makePlatformPrivateKey.sh -- Translate key to PuTTY format
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

if [[ ! -e "$HOME/.ssh/id_rsa.ppk" ]]; then
    get_rsync_for_windows
    echo "---------------------------------------------------------"
    echo "No PuTTY format private key available.  Creating one now."
    echo "---------------------------------------------------------"
    echo
    echo "PuTTYgen should pop up, but first you will get a dialog box saying"
    echo "it has successfully imported a foreign OpenSSH SSH-2 private key."
    echo
    echo "1. Click OK on the 'PuTTYgen Notice' dialog box about the" \
         "successful import."
    echo
    echo "2. Click the 'Save private key' button."
    echo
    echo "3. When asked if you are sure you want to save this key without a"
    echo "   passphrase to protect it, click 'Yes.'"
    echo
    echo "4. In the 'file name:' field, type the exact text below" \
         "INCLUDING the quotes:"
    echo
    echo "   \"%USERPROFILE%\\.ssh\\id_rsa.ppk\""
    echo
    echo "5. Click the 'Save' button in the file dialog and close PuTTYgen" \
         "to continue."
    echo
    echo "NOTE: The first time we test installing this key, you will have to"
    echo "enter your password, perhaps twice.  Subsequent attempts will not"
    echo "ask you again since your key itself will be used for authentication."
    echo
    "${MSYSRSYNCPATH}\\bin\\puttygen.exe" "$USERPROFILE\\.ssh\\id_rsa"
fi
status=0
if [[ ! -e "$HOME/.ssh/id_rsa.ppk" ]]; then
    echo Failed to create a putty-format private key.
    pause
    status=1
fi
if [[ $status != 0 ]]; then
    exit
fi
