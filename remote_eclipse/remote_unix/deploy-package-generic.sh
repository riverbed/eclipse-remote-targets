#! /bin/bash
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

doDeployCmd()
{
    local ssh_cmd="$@"
    echo "$REMOTEDEPLOYHOST>" $ssh_cmd
    ssh $REMOTEDEPLOYUSER@$REMOTEDEPLOYHOST $ssh_cmd
}

deployPackageMain()
{
    if [[ -z "$REMOTEDEPLOYHOST" ]] || \
       [[ "$REMOTEDEPLOYHOST" == "none" ]]; then
        return 0
    fi

    if [ -e ./deploy-override.sh ]; then
        echo ./deploy-override.sh
        ./deploy-override.sh
        local errorstatus=$?
        return $errorstatus;
    fi

    pushd $PACKAGE_PATH >& /dev/null
    # Sort by date, newest at the top, then exclude packages that match a
    # certain pattern (if there are more than one) and then grab only 1
    PACKAGE_FILENAME="$(ls -t *.t[bg]z | egrep -v -e "${PACKAGE_EXCLUDE}" | \
        head -n 1)"
    popd >& /dev/null

    if [ -z "$PACKAGE_FILENAME" ]; then
        exit_with_error "No package found on build host."
    fi

    DEPLOY_PATH=/u1/tmp/$USER

    echo
    echo Deploying package $PACKAGE_FILENAME to $REMOTEDEPLOYHOST....

    doDeployCmd mkdir -p $DEPLOY_PATH
    if [ "$?" != "0" ]; then
        exit_with_error "Creation of deployment path failed."
    fi

    scp $PACKAGE_PATH/$PACKAGE_FILENAME \
        "$REMOTEDEPLOYUSER@$REMOTEDEPLOYHOST:$DEPLOY_PATH/$PACKAGE_FILENAME"

    if [ "$?" != "0" ]; then
        exit_with_error "Package copy failed."
    fi

    echo "Package copied. Stopping the warden."
    echo

    if [ "$PACKAGE_STOPWARDEN" == "true" ]; then
        doDeployCmd /usr/local/etc/rc.d/090.npwarden.sh stop
    fi

    DEPLOY_FILE=$DEPLOY_PATH/$PACKAGE_FILENAME

    local rc=/usr/NPcli/abin/release-current

    if [ -n "$PACKAGE_DELETE" ]; then
        doDeployCmd "pkg_delete $PACKAGE_DELETE; pkg_add $DEPLOY_FILE"
    else
        doDeployCmd "pkg_replace -d $DEPLOY_FILE"
    fi
    if [ "$?" != "0" ]; then
        exit_with_error "Package replace failed."
    fi

    if [ "$PACKAGE_REBOOT" == "true" ]; then
        echo
        echo "Rebooting the appliance."
        echo
        doDeployCmd "$rc; nohup sh -c '/sbin/shutdown -r now' >& /dev/null &"
    else
        echo
        echo "Restarting the warden."
        echo
        if [ "$PACKAGE_STOPWARDEN" == "true" ]; then
            doDeployCmd "/usr/local/etc/rc.d/090.npwarden.sh start; $rc"
        else
            doDeployCmd "/usr/local/etc/rc.d/090.npwarden.sh restart; $rc"
        fi
    fi
    return 0
}

deployPackageMain "$@"