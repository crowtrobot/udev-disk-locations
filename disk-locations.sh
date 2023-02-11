#!/bin/bash
#
# Called from udev rule, this script will try to help set some links to 
# tell you about where that specific disk is.  
# 
# For example, replace the failed drive in an md raid:
#   mdadm --manage /dev/md0 add /dev/disk/by-location/left_drive_bay
#


location-error() {
    echo "$1" 1>2&
    LOCATION_ERROR="$LOCATION_ERROR - $1"
    echo "LOCATION_ERROR=$LOCATION_ERROR" > /tmp/location_error
}


if [[ $ACTION == remove ]] ; then
    echo "$ACTION, nothing to do" >> /tmp/aaaa    
    exit 0
fi

#location-error "running"

# Find the driver, and call the appropriate helper for that driver
if [[ -z $ID_PATH ]] ; then
    location-error "ID_PATH not set"
    exit 0
fi

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
Interface_path="$( echo ${DEVPATH} | cut -d / -f 1-5 )"
Interface_path2="$( echo ${DEVPATH} | cut -d / -f 1-4 )"

Interface_Driver=none
for path in "/sys/${Interface_path}/driver" "/sys/${Interface_path2}/driver" ; do
    if [[ -L $path ]] ; then
	tmp="$(basename "$( realpath "$path" )" )"
	if [[ $tmp == "pcieport" ]] ; then
	    continue
	fi
	Interface_Driver="$tmp"
    fi
done
	    
if [[ $Interface_Driver == none ]] ; then
    location-error "No driver found"
    exit 1
fi

driver_helper_script="${SCRIPTPATH}/location-helper-${Interface_Driver}.sh"
if [[ -e $driver_helper_script ]] ; then
    . "$driver_helper_script"
else
    location-error "No driver helper found for $Interface_Driver" 
fi

