#!/bin/bash
#
# The helper specific to ahci.  Effectively just look up the name(s) from
# the ini file, and if they are found add those names in /dev/disk/by-location
#
# Identify disk by SATA part, like ata5, and assign a name, like "top".
# ata5=top
#

location-error() {
    echo "$1" 1>2&
    LOCATION_ERROR="$LOCATION_ERROR - $1"
    echo "LOCATION_ERROR=$LOCATION_ERROR" > /tmp/location_error
}

ata_name="$( echo "$DEVPATH" | cut -d / -f 5 )"
# should be something like ata5

# Interface_Driver should have been set by the script that called this one
# SCRIPTPATH should also be set by calling script

names_file="${SCRIPTPATH}/location_names_${Interface_Driver}.ini"
if [[ -e $names_file ]] ; then
    #This does a subshell, don't want that
    #grep -i "^${ata_name}=" "$names_file" | while read line ; do
    while read line ; do
	name="$( echo "$line" | cut -d '=' -f 2 )"
	echo "disk/by-location/${name}"
    done < <(grep -i "^${ata_name}=" "$names_file") #no-subshell this way?
else
    location-error "${names} file doesn't exist"
    exit 1
fi



