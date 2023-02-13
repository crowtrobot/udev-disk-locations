# udev-disk-locations
Scripts to extend udev to automate tagging disks with physical location data.  Creates additional links for drives, for example "/dev/disk/by-location/front-bay1" or "/dev/disk/by-location/top-left" as links to the device like /dev/sda.  


# Why?
Sometimes it's nice to know what disk you are dealing with.  I am responsible for a few servers with old RAID cards, but without a RAID.  The drives are presented individually to the OS,  There seems to be a few names for this, JBOD mode, single mode, or HBA mode.  On some of these machines, the drive locate LEDs don't work.

It is annoying, especially when in a hurry, to try to figure out which drive was the one that needed to be replaced.  Figuring out which drive is /dev/sdd meant doing these steps:

1.  udevadm info /dev/sdd, note the HCTL scsi address, and the PCI address for the controller
2.  storcli /call show.  Match the PCI address to a controller.
3.  storcli /c$controler_nmber show.  Match the target number from the HCTL to a disk's DID (disk ID number).  From that find the enclosure and slot numbers.
4.  Figure out where that enclosue is (for example, maybe its the front of the top JBOD box).
5.  Figure out which bay is that slot number

# So how does it work?
A udev rule will happen on every drive (not the partitions, just the drives).  This will run the script /opt/udev-disk-location/disk-location.sh.  The rule looks like this

KERNEL=="sd[a-z]*", ENV{SUBSYSTEM}=="block", ENV{DEVPATH}=="/devices/pci?*", PROGRAM="/opt/udev-disk-locations/disk-locations.sh" SYMLINK+="%c{1+}"

disk-location.sh will find out what driver is used for the drive interface.  This is usually AHCI for the SATA controllers on the motherboard, and I have some servers that use megaraid_sas driver for the RAID controller.  This will then start the helper for that driver, like location-helper-megaraid_sas.sh.  That script will get the drive location names from its config file, like location_names_megaraid_sas.ini.  The format for that config is specific to the driver (because it's much more complicated with those raid cards than it is with the simple AHCI motherboard SATA controller).


## AHCI ini config format
Technically this could all be easily achieved normal udev rules, but since this script existed anyway for the other drives, why not use it for these too?  
For AHCI, the names are simply specified like:
ata5=back-left
ata6=back-right

One drive can have more than one name, each will become a link in /dev/disk/by-location:
ata5=back-left
ata5=near_the_power_supply
ata6=near_the_usb

# megaraid_sas ini config format
For the megaraid_sas, the names are more complicated.  First you need to name the enclosure.  This is identified as a combination of the PCI address for the raid card (because you might have more than one raid card) and the enclosure number.  For example, with raid card at pci-0000:01:00.0, and enclosures 4 and 5:
pci-0000:01:00.0/4=jbod1_front
pci-0000:01:00.0/5=jbod1_back

Then you can use that name with the slot number to identify a drive bay.  For consistency we have decided that all drive bays are numbered starting at 1, from left to right, and bottom to top.  But this enclosure numbers starting from 0, from the bottom-left corner going up.  So:

jbod1_front/0=bay_1
jbod1_front/1=bay_5
jbod1_front/1=bay_9

etc.

# Installation
To start using this, simply clone this project, and then copy or move that directory to /opt/udev-disk-locations/ so that the disk-locations.sh script is at /opt/udev-disk-locations/disk-locations.sh.  Copy 81-disks-by-location.rules into the /etc/udev/rules.d/ directory.  Then make your .ini file(s)
