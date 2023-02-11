#!/bin/bash
#
# Get the location of JBOD-mode disks for megaraid in a 2U (3-row) case with SAS expander
#
#

# This was for debug originally, but storcli spits out some debug log files of its own, so lets give
# them a place to land.  
mkdir -p /tmp/udev_helper
cd /tmp/udev_helper

#Debug logging
DBG=false
if [[ $DBG == true ]] ;then
    debug_file=$(mktemp -p /tmp/udev_helper/) 
    printenv > "$debug_file"
    exec > >(tee -ai "$debug_file")
    exec 2>&1
    set -x
fi


# map enclosure slot to bay number
declare -arx Slot_to_bay=([0]="1" [1]="5" [2]="9" [3]="2" [4]="6" [5]="10" [6]="3" [7]="7" [8]="11" [9]="4" [10]="8" [11]="12")

# Get the PCI address for this interface from the udev variables
# I know devpath is there, but lets try ID_PATH might be easier to deal with
# DEVPATH=/devices/pci0000:00/0000:00:01.0/0000:01:00.0/host0/target0:0:18/0:0:18:0/block/sde
# ID_PATH=pci-0000:03:00.0-scsi-0:0:17:0


HCTL="$( echo $ID_PATH | grep -io '[0-9a-f]*:[0-9a-f]*:[0-9a-f]*:[0-9a-f]*$' )"
HCTL_H="$( echo $HCTL | cut -d : -f 1 )"
HCTL_C="$( echo $HCTL | cut -d : -f 2 )"
HCTL_T="$( echo $HCTL | cut -d : -f 3 )"
HCTL_L="$( echo $HCTL | cut -d : -f 4 )"

if [[ $HCTL_C != 0 ]] ; then
echo "non-zero HCTL controller number suggests this is a raid" 1>&2
exit 0
fi

if [[ -z $ID_PATH ]] ; then
echo "ID_PATH not set" 1>&2
exit 0
fi

pci="$( echo ${ID_PATH} | grep -io "^pci-[0-9a-f]*:[0-9a-f]*:[0-9a-f]*\.[0-9a-f]*" |sed 's/pci-//g' )"
# First part of PCI location, chop the leading 2 zeros off, so it looks lke 00
#pci_1="$( echo ${pci} | cut -d : -f 1 | sed 's/^00//g' )"


pci_1="$( printf "%02x\n" "0x$( echo ${pci} | cut -d : -f 1 )" )"
pci_2="$( echo ${pci} | cut -d : -f 2 )"
pci_3="$( echo ${pci} | cut -d : -f 3 | grep -io "^[0-9a-f]*" )"
pci_4="$( printf "%02x\n" "0x$( echo ${pci} | grep -io "[0-9a-f]*$" )" )"

pci_to_compare="${pci_1}:${pci_2}:${pci_3}:${pci_4}"

# Get the interface part of the path to find the driver
Interface_path="$( echo ${DEVPATH} | cut -d / -f 1-5 )"
Interface_Driver="$(basename "$( realpath "/sys/${Interface_path}/driver" )" )"

storcli=/usr/local/bin/storcli
if [[ ! -x "$storcli" ]] ; then
    echo "no storcli command to run" 1>&2
    exit 1
fi


#Loop through raidcards from storcli:
for card in $( $storcli show J | jq '.Controllers[0]."Response Data"."System Overview"[].Ctl') ; do
    storcli_card_show="$( $storcli /c${card} show J )"

    #debug
    if [[ $DBG == true ]] ;then
	echo "------" >> "$debug_file"    
	echo "$storcli_card_show" >> "$debug_file"
	echo "------" >> "$debug_file"
    fi
    
    # Don't bother if this card isn't using the same driver
    stor_driver="$( echo "${storcli_card_show}" | jq -r '.Controllers[0]."Response Data"."Driver Name"' )"
    if [[ $stor_driver != $Interface_Driver ]]; then
       continue
    fi

    # Don't bother if the PCI location isn't the same
    stor_pci="$( echo "${storcli_card_show}" | jq -r '.Controllers[0]."Response Data"."PCI Address"')"
    if [[ $stor_pci != $pci_to_compare ]] ;then
       continue
    fi

    # This should be done in some config file or something, but whatever
    # There should be an eclosure_name[$card][$enclosure]=jbod1-front (or maybe PCI ID instead of $card), and then a slot_to_bay[$card][$enclosure][$slot]=5
    #  so that it is possible to echo "ID_AJB_BAY=eclosure_name[$card][$enclosure]-bay-slot_to_bay[$card][$enclosure][$slot]" to get "ID_AJB_BAY=jbod2_U13-16_front-bay-4"
    # pick the enclosures that are recognized and usable
#    for enc in $( echo "${storcli_card_show}" | jq -r '.Controllers[0]."Response Data"."Enclosure LIST"[]."EID"' ) ; do
    # Try thi instead - jq -r '.Controllers[0]."Response Data"."Properties"[]."EID"'
    storcli_card_enc_show="$( $storcli /c${card}/eall show J )"
        for enc in $( echo ${storcli_card_enc_show}  | jq -r '.Controllers[0]."Response Data"."Properties"[]."EID"' ) ; do
	# enc_slots="$( echo  "${storcli_card_show}" | jq -r --argjson e $enc '.Controllers[0]."Response Data"."Enclosure LIST"[] | select(.EID==$e).Slots' )"
	# enc_id="$( echo  "${storcli_card_show}" | jq -r --argjson e $enc '.Controllers[0]."Response Data"."Enclosure LIST"[] | select(.EID==$e)."ProdID"' )"
	enc_slots="$( echo  "${storcli_card_enc_show}" | jq -r --argjson e $enc '.Controllers[0]."Response Data"."Properties"[] | select(.EID==$e).Slots' )"
	enc_id="$( echo  "${storcli_enc_card_show}" | jq -r --argjson e $enc '.Controllers[0]."Response Data"."Properties"[] | select(.EID==$e)."ProdID"' )"
	if [[ $enc_slots != 12 ]] ; then
	    Enclosure[$card,$enc]="nogood wrong number of slots"
	    continue
	fi
	# if [[ $enc_id != "SC826P" ]] || [[ $enc_id != "SAS2X28" ]] ; then # I have 2 models, and I don't really think they need to be checked anyway
	#     Enclosure[$card,$enc]="nogood, wrong model"
	#     continue
	# fi
	Enclosure[$card,$enc]=good
    done

# jq --arg a 18    makes $a the sring "18" so no usable as a number
# jq --argjson a 18   seems to let $a be thee number 18.  I think I hate json

#    E_S="$( echo "${storcli_card_show}" | jq -r --argjson a "$HCTL_T" '.Controllers[]."Response Data"."JBOD LIST"[] | select(.DID==$a)."EID:Slt"' )"
    E_S="$( echo "${storcli_card_show}" | jq -r --argjson a "$HCTL_T" '.Controllers[]."Response Data"."PD LIST"[] | select(.DID==$a)."EID:Slt"' )"

    Expander="$( echo $E_S | cut -d : -f 1 )"
    Slot="$( echo $E_S | cut -d : -f 2 )"

    if [[ ${Enclosure[${card},${Expander}]} == good ]] ; then
	echo "ID_AJB_KNOWN=yes"
	echo "ID_AJB_BAY=front_bay-${Slot_to_bay[$Slot]}"
	echo "ID_AJB_SLOT=megaraid-card-${card}_enclosure-${Expander}_slot-${Slot}"
	exit 0
    else
	echo "Maybe a bug?  Bad enclossure" 1>&2
    fi

done
