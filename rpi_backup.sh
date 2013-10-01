#!/bin/bash
# raspberry pi backup
# Writed by Andrey Derevyagin on 30/09/2013

# Settings 
SRC_DISK_PATH="/dev/mmcblk0"
DST_DISK="sda"
BACKUP_LOCATION="/mnt/backup_flash"
#NAME=date +"%d_%m_%Y"
#NAME="rpi.img" 
RSYNC_OPTIONS_OLD="-aEv --delete-during"
RSYNC_OPTIONS="--force -rltWDEgopt"
FORCE_INITIALIZE=false

SERVICES="/etc/init.d/cron \
/etc/init.d/logitechmediaserver \
/etc/init.d/mediatomb
/etc/init.d/mumble-server \
/etc/init.d/samba \
/etc/init.d/squeezeslave \
/etc/init.d/transmission-daemon \
/etc/init.d/twonky \
/etc/init.d/pptpd \
/etc/init.d/lighttpd"


SCRIPT=`basename $0`
DST_ROOT_PARTITION=/dev/${DST_DISK}2
DST_BOOT_PARTITION=/dev/${DST_DISK}1



# Check for root user
if [ `id -u` != 0 ]
then
    echo -e "$SCRIPT needs to be run as root.\n"
    exit 1
fi


 
# Borrowed from do_expand_rootfs in raspi-config
expand_rootfs()
        {
        # Get the starting offset of the root partition
        PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^2" | cut -f 2 -d:)
        [ "$PART_START" ] || return 1
        # Return value will likely be error for fdisk as it fails to reload the
        # partition table because the root fs is mounted
        fdisk /dev/$DST_DISK > /dev/null <<EOF
p
d
2
n
p
2
$PART_START
 
p
w
q
EOF
        }


# Here, the program will look for some common installed programs and disables them for a while so that the backup has less chance to fail.. ^^
# Or of course you can add it yourself.
services_action()
{
    for i in $SERVICES
    do
      if test -f $i
      then
            #echo "$i ${1}ing"
            $i $1
      fi
    done
}


START_TIME=`date '+%H:%M:%S'`

#Cron_location="/etc/cron.d/SafeMyPi"
#Cron_setting=$"0 30 * * 1 root /bin/sh  /root/SafeMyPi"
###################################################
#if grep -Fxq $Cron_location $Cron_setting
#then
#    echo "Line is found! Skipping... ^^"
#else
#    echo "Line not found! Adding line..."
#    echo $Cron_setting >> $Cron_location
#fi
#################################################


if ! cat /proc/partitions | grep -q $DST_DISK
then
        echo "Destination disk '$DST_DISK' does not exist."
        echo "Plug the destination SD card into a USB port."
        echo "If it does not show up  as '$DST_DISK', then do a"
        echo -e "'cat /proc/partitions' to see where it might be.\n"
        exit 1
fi

TEST_ROOT_MOUNTED=`fgrep " $BACKUP_LOCATION " /etc/mtab | cut -f 1 -d ' ' `
if [[ "$TEST_ROOT_MOUNTED" != "" && "$TEST_ROOT_MOUNTED" != "$DST_ROOT_PARTITION" ]]
then
        echo "This script uses $BACKUP_LOCATION for mounting filesystems, but"
        echo "$BACKUP_LOCATION is already mounted with $TEST_ROOT_MOUNTED."
        echo -e "Unmount $BACKUP_LOCATION before running this script.\n"
        exit 1
fi

TEST_BOOT_MOUNTED=`fgrep " $BACKUP_LOCATION/boot " /etc/mtab | cut -f 1 -d ' ' `
if [[ "$TEST_BOOT_MOUNTED" != "" && "$TEST_BOOT_MOUNTED" != "$DST_BOOT_PARTITION" ]]
then
        echo "This script uses ${BACKUP_LOCATION}/boot for mounting filesystems, but"
        echo "${BACKUP_LOCATION}/boot is already mounted with $TEST_BOOT_MOUNTED."
        echo -e "Unmount $BACKUP_LOCATION before running this script.\n"
        exit 1
fi


# Check that none of the destination partitions are busy (mounted).
DST_ROOT_CURMOUNT=`fgrep "$DST_ROOT_PARTITION " /etc/mtab | cut -f 2 -d ' ' `
DST_BOOT_CURMOUNT=`fgrep "$DST_BOOT_PARTITION " /etc/mtab | cut -f 2 -d ' ' `
 
if [[ "$DST_ROOT_CURMOUNT" != "" && "$DST_ROOT_CURMOUNT" != "$BACKUP_LOCATION" ]] || \
   [[ "$DST_BOOT_CURMOUNT" != "" && "$DST_BOOT_CURMOUNT" != "${BACKUP_LOCATION}/boot" ]]
then
        echo "A destination partition is busy (mounted).  Mount status:"
        echo "    $DST_ROOT_PARTITION:  $DST_ROOT_CURMOUNT"
        echo "    $DST_BOOT_PARTITION:  $DST_BOOT_CURMOUNT"
        echo -e "Aborting!\n"
        exit 1
fi

SRC_BOOT_PARTITION_TYPE=`parted /dev/mmcblk0 -ms p | grep "^1" | cut -f 5 -d:`
SRC_ROOT_PARTITION_TYPE=`parted /dev/mmcblk0 -ms p | grep "^2" | cut -f 5 -d:`
DST_BOOT_PARTITION_TYPE=`parted /dev/$DST_DISK -ms p | grep "^1" | cut -f 5 -d:`
DST_ROOT_PARTITION_TYPE=`parted /dev/$DST_DISK -ms p | grep "^2" | cut -f 5 -d:`

# use dd to initialize flash
if [ "$DST_BOOT_PARTITION_TYPE" != "$SRC_BOOT_PARTITION_TYPE" ] || \
   [ "$DST_ROOT_PARTITION_TYPE" != "$SRC_ROOT_PARTITION_TYPE" ] || \
   [ "$FORCE_INITIALIZE" = "true" ]
then
        if [[ "$TEST_ROOT_MOUNTED" != "" || "$TEST_BOOT_MOUNTED" != "" ]]
        then
            echo "A destination partition is busy (mounted). Can't write image to device."
            echo "Mount status:"
            echo "    $DST_ROOT_PARTITION:  $DST_ROOT_CURMOUNT"
            echo "    $DST_BOOT_PARTITION:  $DST_BOOT_CURMOUNT"
            echo -e "Aborting!\n"
            exit 1
        fi
  
        echo ""
        if [ "$FORCE_INITIALIZE" = "true" ]
        then
                echo "*** Forcing a partition initialization of destination '$DST_DISK' ***"
        fi
 
        echo "The existing partitions on destination disk '$DST_DISK' are:"
#       fdisk -l /dev/$DST_DISK | grep $DST_DISK
        parted /dev/$DST_DISK unit MB p \
                | sed "/^Model/d ; /^Sector/d"
        if [ "$DST_BOOT_PARTITION_TYPE" != "$SRC_BOOT_PARTITION_TYPE" ]
        then
                echo -e "  ... Cannot find a destination boot file system of type: $SRC_BOOT_PARTITION_TYPE\n"
        fi
        if [ "$DST_ROOT_PARTITION_TYPE" != "$SRC_ROOT_PARTITION_TYPE" ]
        then
                echo -e "  ... Cannot find a destination root file system of type: $SRC_ROOT_PARTITION_TYPE\n"
        fi
        echo "This script can initialize the destination disk with a partition"
        echo "structure copied from the currently booted filesytem and then resize"
        echo "partition 2 (the root filesystem) to use all space on the SD card."

        # Image onto the destination disk a beginning fragment of the
        # running SD card file structure that spans at least more than
        # the start of partition 2.
        #
        # Calculate the start of partition 2 in MB for the dd.
        PART2_START=$(parted /dev/mmcblk0 -ms unit MB p | grep "^2" \
                    | cut -f 2 -d: | sed s/MB// | tr "," "." | cut -f 1 -d.)
        # and add some slop
        DD_COUNT=`expr $PART2_START + 8`
 
        services_action stop

        echo ""
        echo "Imaging the partition structure, copying $DD_COUNT megabytes..."
        dd if=/dev/mmcblk0 of=/dev/$DST_DISK bs=1M count=$DD_COUNT
 
        # But, though Partion 1 is now imaged, partition 2 is incomplete and
        # maybe the wrong size for the destination SD card.  So fdisk it to
        # make it fill the rest of the disk and mkfs it to clean it out.
        #
        echo "Sizing partition 2 (root partition) to use all SD card space..."
        expand_rootfs
        mkfs.ext4 $DST_ROOT_PARTITION > /dev/null
 
        echo ""
        echo "/dev/$DST_DISK is initialized and resized.  Its partitions are:"
#        fdisk -l /dev/$DST_DISK | grep $DST_DISK
        parted /dev/$DST_DISK unit MB p | sed "/^Model/d ; /^Sector/d"
 
        SRC_ROOT_VOL_NAME=`e2label /dev/mmcblk0p2`
        echo ""
        echo "Your booted /dev/mmcblk0p2 rootfs existing label: $SRC_ROOT_VOL_NAME"
        if [ "$SRC_ROOT_VOL_NAME" != "" ]
        then
            e2label $DST_ROOT_PARTITION $SRC_ROOT_VOL_NAME
        fi
else
    services_action stop
fi

DST_ROOT_VOL_NAME=`e2label $DST_ROOT_PARTITION`
if [ "$DST_ROOT_VOL_NAME" = "" ]
then
    DST_ROOT_VOL_NAME="no label"
fi
 
echo ""
echo "Clone destination disk   :  $DST_DISK"
echo "Clone destination rootfs :  $DST_ROOT_PARTITION ($DST_ROOT_VOL_NAME) on ${BACKUP_LOCATION}"
echo "Clone destination bootfs :  $DST_BOOT_PARTITION on ${BACKUP_LOCATION}/boot"
#echo "Verbose mode             :  $VERBOSE"
 

# Mount destination filesystems.
if [ "$TEST_ROOT_MOUNTED" != "$DST_ROOT_PARTITION" ]
then
    echo "=> Mounting $DST_ROOT_PARTITION ($DST_ROOT_VOL_NAME) on $BACKUP_LOCATION"
    if ! mount $DST_ROOT_PARTITION $BACKUP_LOCATION
    then
        echo -e "Mount failure of $DST_ROOT_PARTITION, aborting!\n"
        services_action start
        exit 1
    fi
fi

if [ ! -d $BACKUP_LOCATION/boot ]
then
    mkdir $BACKUP_LOCATION/boot
fi
 
if [ "$TEST_BOOT_MOUNTED" != "$DST_BOOT_PARTITION" ]
then
    echo "=> Mounting $DST_BOOT_PARTITION on $BACKUP_LOCATION/boot"
    if ! mount $DST_BOOT_PARTITION $BACKUP_LOCATION/boot
    then
        umount $BACKUP_LOCATION
        echo -e "Mount failure of $DST_BOOT_PARTITION, aborting!\n"
        services_action start
        exit 1
    fi
fi

# Now we are going to make the backup
# Please be reminded to double-check your settings down below because if wrong, They will destroy your sd card!!
if test -e $BACKUP_LOCATION
then
   if test -e $SRC_DISK_PATH
   then
      sync
      echo "Starting the filesystem rsync to $DST_DISK"
#      dd if=$SRC_DISK_PATH conv=sync,noerror bs=512K | gzip > $BACKUP_LOCATION/$NAME.gz
      rsync $RSYNC_OPTIONS     \
            --exclude /dev/    \
            --exclude /lost\+found/ \
            --exclude /media/  \
            --exclude /mnt/    \
            --exclude /proc/   \
            --exclude /run/    \
            --exclude /sys/    \
            --exclude /tmp/    \
            --exclude /var/cache/davfs2/ \
            / $BACKUP_LOCATION/
      status=$?
#      if test -e "$BACKU_LOCATION/$NAME"
      if [ $status -ne 0 ];
      then
         echo "Rsync backup Failed!"
         echo "*Cries*"
      else
         echo "Rsync backup Succesfull!!"
         echo "*cheers*"
      fi

      # fix system directories
      echo "Check system dirs..."
      for i in dev media mnt proc run sys
      do
        if [ ! -d $BACKUP_LOCATION/$i ]
        then
          mkdir $BACKUP_LOCATION/$i
        fi
      done
      if [ ! -d $BACKUP_LOCATION/tmp ]
      then
        mkdir $BACKUP_LOCATION/tmp
        chmod a+w $BACKUP_LOCATION/tmp
      fi
      # Some extra optional dirs I create under /mnt
      for i in `ls /mnt/ | xargs`
      do
        if [ ! -d $BACKUP_LOCATION/mnt/$i ]
        then
          mkdir $BACKUP_LOCATION/mnt/$i
        fi
      done
   else
      echo "SD card not found!!"
      echo "Please specify the location of your Sd card"
      echo "For more information.. Please go to the Raspberry Pi forums at http://www.raspberrypi.org/phpBB3/"
   fi
else
   echo "Your Backup location cannot be found!!"
   echo "Specify the location of your backup in the settings!!"
fi

# unmount  if need
if [ "$TEST_BOOT_MOUNTED" != "$DST_BOOT_PARTITION" ]
then
    echo "unmounting $BACKUP_LOCATION/boot"
    umount $BACKUP_LOCATION/boot
fi

if [ "$TEST_ROOT_MOUNTED" != "$DST_ROOT_PARTITION" ]
then
    echo "unmounting $BACKUP_LOCATION"
    umount $BACKUP_LOCATION
fi

# Now the backup is done, whe are starting the services again.. ;)
echo "Starting the services"
for i in $SERVICES
do
  if test -f $i
  then
        $i start
  fi
done

STOP_TIME=`date '+%H:%M:%S'`
 
echo ""
echo "*** Done with clone to /dev/$DST_DISK ***"
echo "    Started: $START_TIME    Finished: $STOP_TIME"
echo ""
