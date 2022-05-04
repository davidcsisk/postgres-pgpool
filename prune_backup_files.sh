#!/usr/bin/bash

if [ -z "$1" ] || [ "$1" == '--help' ] || [ "$1" == '-h' ] ; then
   echo "Usage: v1.1...prune backup files by age, day of week, and day of month, to reflect retainment schedule."
   echo ""
   echo "./prune_backup_files.sh 'directory_and_filespec'"
   echo ""
   echo "This script prunes hotbackup directories and dump files based on this retainment schedule:"
   echo " - Latest 7 days:   Keep backup of each day"
   echo " - Latest 4 weeks:  Keep 1 backup from each week (Sun)" 
   echo " - Latest 3 months: Keep 1 backup from each month (1st of month)" 
   echo " Use this script for hotbackups and dumps only...do not use this script for WAL archives."
   echo
   echo "Examples:"
   echo "  ./prune_backup_files.sh '/data/pg96/backups/rtp/*' "
   echo "  ./prune_backup_files.sh '/data/pg96/dumps/rtp/*' "
   echo
   exit 0;
fi

FINDPATH="$1"

STARTCOUNT=`ls -d -tr $FINDPATH | wc -l`

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Start backup file pruning on $FINDPATH...$STARTCOUNT files/directories present."

for FILE in `ls -d -tr $FINDPATH`
do
  # Get file/directory age in days,  day-of-week (Sun = 7), and day-of-month
  FILEAGE=`echo $((($(date +%s) - $(date +%s -r "$FILE")) / 86400))`   
  FILEDOW=`date -r "$FILE" +"%u"`                                      
  FILEDOM=`date -r "$FILE" +"%e"`                                      

  if [ -z "$FILEAGE" -o -z "$FILEDOW" -o -z "$FILEDOM" ]; then
     echo "ERROR: Unable to get file/directory age, day of week, and/or day of month for $FILE"
     exit 1;
  fi

  # Remove anything over 93 days old
  if [ "$FILEAGE" -gt "93" ]; then 
     rm -rf $FILE
     echo "      REMOVING $FILE (age=$FILEAGE)"
  fi
  # Remove anything over 31 days old AND not from the 1st day of the month
  if [ "$FILEAGE" -gt "34" -a "$FILEAGE" -le "93" -a "$FILEDOM" -ne "1" ]; then
     rm -rf $FILE
     echo "      REMOVING $FILE (age=$FILEAGE dom=$FILEDOM)"
  fi
  # Remove anything over 7 days old AND not from 1st day of month AND not from Sun
  if [ "$FILEAGE" -gt "7" -a "$FILEAGE" -le "34" -a "$FILEDOM" -ne "1" -a "$FILEDOW" -ne "7" ]; then
     rm -rf $FILE
     echo "      REMOVING $FILE (age=$FILEAGE dom=$FILEDOM dow=$FILEDOW)"
  fi
done
echo; echo "Retained files/directories:"
ls -d -ltr $FINDPATH; echo

ENDCOUNT=`ls -d -tr $FINDPATH | wc -l`
date "+%a_%Y-%m-%d_%H:%M:%S - Completed backup file pruning on $FINDPATH...$ENDCOUNT files/directories remaining."; echo

