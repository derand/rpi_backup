#!/bin/bash
# copy work to webdav disk

BACKUP_MOUNT_LOCATION=/mnt/backup
BACKUP_LOCATION=${BACKUP_MOUNT_LOCATION}/rpi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SETTINGS="$DIR/settings"

MYSQL_USER=`grep MYSQL_USER $SETTINGS | cut -f 2 -d '=' `
MYSQL_DB=`grep MYSQL_DB $SETTINGS | cut -f 2 -d '=' `

if ! test -e $BACKUP_LOCATION
then
    if ! sudo mount $BACKUP_MOUNT_LOCATION
    then
    	echo "Can't mount $BACKUP_MOUNT_LOCATION"
    	exit 1
    fi
fi

mysqldump -u "$MYSQL_USER" "$MYSQL_DB" > ${BACKUP_LOCATION}/${MYSQL_DB}.mysql
rsync -ruv --size-only --inplace --delete-during /home/pi/share/ ${BACKUP_LOCATION}/share/
