#!/usr/bin/bash

if [ -z "$1" ] || [ "$1" == '--help' ] || [ "$1" == '-h' ] ; then
   echo "Version 1.0 collect-pgpool-logs.sh...collect and tarball pgpool logs and config for PGPool support ticket"
   echo "Usage: "
   echo 
   echo "./collect-pgpool-logs.sh [no arguments] | -h | --help (Display this help)"
   echo 
   echo "./collect-pgpool-logs.sh host1,host2,host3 [non-default logfile name)"
   echo 
   exit 0;
fi

DEFAULTLOGFILE="pgpool.log"
DBHOSTS="$1"
LOGFILE="$2"
DATESTRING=`date +%Y%m%d-%H%M%S`

if [ -z "$LOGFILE" ]; then LOGFILE="$DEFAULTLOGFILE"; fi

# Loop thru db hosts
for DBHOST in ${DBHOSTS//,/ }; do
    echo "DBHOST=$DBHOST   LOGFILE=$LOGFILE"
    scp ${DBHOST}:/var/log/${LOGFILE} /tmp/pgpool-${DATESTRING}_${DBHOST}_${LOGFILE}
    scp ${DBHOST}:/etc/pgpool-II/pgpool.conf /tmp/pgpool-${DATESTRING}_${DBHOST}_pgpool.conf
done
tar cvfz /tmp/pgpool-support-files_${DATESTRING}.tar.gz /tmp/pgpool-${DATESTRING}*

