#! /bin/bash
#
# The part that specific to the megaraid_sas driver.  This is a bit 
# complicated.
#
# Obviously not relevant for a raid, sine that occupies more than one drive.
# 
# The SCSI ID 0:0:18:0, which is host 0, controller 0, target 18, lun 0.  
# The target 18, matches what storcli will list as the DID (drive id) of 18.
# From that we will get the enclosure number and slot number, which relate
# directly to the physical location.
#
# 

location-error() {
    echo "$1" 1>2&
    LOCATION_ERROR="$LOCATION_ERROR - $1"
    echo "LOCATION_ERROR=$LOCATION_ERROR" > /tmp/location_error
}


storcli=/usr/local/bin/storcli
names_file="${SCRIPTPATH}/location_names_${Interface_Driver}.ini"

if [[ ! -x "$storcli" ]] ; then
    locaion-error "no storcli command to run"
    exit 1
fi

HCTL="$( echo $ID_PATH | grep -io '[0-9a-f]*:[0-9a-f]*:[0-9a-f]*:[0-9a-f]*$' )"
HCTL_H="$( echo $HCTL | cut -d : -f 1 )"
HCTL_C="$( echo $HCTL | cut -d : -f 2 )"
HCTL_T="$( echo $HCTL | cut -d : -f 3 )"
HCTL_L="$( echo $HCTL | cut -d : -f 4 )"

if [[ $HCTL_C != 0 ]] ; then
    location-error "non-zero HCTL controller number suggests this is a raid"
    exit 0
fi

if [[ -z $ID_PATH ]] ; then
    location-error "ID_PATH not set" 1>&2
    exit 0
fi

pci="$( echo ${ID_PATH} | grep -io "^pci-[0-9a-f]*:[0-9a-f]*:[0-9a-f]*\.[0-9a-f]*" |sed 's/pci-//g' )"

pci_1="$( printf "%02x\n" "0x$( echo ${pci} | cut -d : -f 1 )" )"
pci_2="$( echo ${pci} | cut -d : -f 2 )"
pci_3="$( echo ${pci} | cut -d : -f 3 | grep -io "^[0-9a-f]*" )"
pci_4="$( printf "%02x\n" "0x$( echo ${pci} | grep -io "[0-9a-f]*$" )" )"

pci_to_compare="${pci_1}:${pci_2}:${pci_3}:${pci_4}"

for card in $( $storcli show J | jq '.Controllers[0]."Response Data"."System Overview"[].Ctl') ; do
    storcli_card_show="$( $storcli /c${card} show J )"

    # Safety check, this isn't the right raid card if it isn't using the
    # same driver.  If that happens just skip to the next card
    stor_driver="$( echo "${storcli_card_show}" | jq -r '.Controllers[0]."Response Data"."Driver Name"' )"
    if [[ $stor_driver != $Interface_Driver ]]; then
       continue
    fi

    # Skip this card if the PCI location isn't the same
    stor_pci="$( echo "${storcli_card_show}" | jq -r '.Controllers[0]."Response Data"."PCI Address"')"
    if [[ $stor_pci != $pci_to_compare ]] ;then
       continue
    fi

    storcli_card_enclosure_show="$( $storcli /c${card}/eall show J )"
  
    # For the drive 0:0:18:0, that 18 is what storcli calls the DID (drive ID)
    # From that ID we want to get the enclosure and slot, which looks like 4:1
    eclosure_slot_this_drive="$( echo "${storcli_card_show}" | jq -r --argjson a "$HCTL_T" '.Controllers[]."Response Data"."PD LIST"[] | select(.DID==$a)."EID:Slt"' )"

    enclosure_id="$( echo $eclosure_slot_this_drive | cut -d : -f 1 )"
    slot_id="$( echo $eclosure_slot_this_drive | cut -d : -f 2 )"
    
    ## Get the enclosure name, and the bay name from the .ini file.  
    if [[ -e "$names_file" ]] ; then
	enclosure_name="$( grep -i "^pci-${pci}/${enclosure_id}=" "$names_file" | head -n 1 | cut -d = -f 2 )"
	if [[ $enclosure_name == "" ]] ; then
	    enclosure_name="enclosure-${enclosure_id}"
	fi

	grep -i "^${enclosure_name}.${slot_id}=" "$names_file" |\
	    cut -d = -f 2 |\
	    while read bay_name ; do
		if [[ $bay_name == "" ]] ; then
		    bay_name="bay-unknown-slot-${slot_id}"
		fi
		
		echo "disk/by-location/${enclosure_name}_${bay_name}"
	    done

	link_slots="$(grep -i "^link_slots=" "$names_file" | cut -d = -f 2)"
	if [[ $link_slots =~ yes ]] || [[ $link_slots =~ true ]] ; then
	    echo "disk/by-location/megaraid-card-${card}_enclosure-${enclosure_name}_slot-${slot_id}"
	fi
	
    else
	# If there's no name file, we still know the card, eclosure, and slot
	echo "disk/by-location/megaraid-card-${card}_enclosure-${enclosure_id}_slot-${slot_id}"
    fi

done

