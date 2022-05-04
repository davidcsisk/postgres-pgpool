#!/usr/bin/bash

if [ -z "$1" ] || [ "$1" == '--help' ] || [ "$1" == '-h' ] ; then
   echo "pghotbackup.sh v1.1"
   echo "Usage: Execute hot backup of database instance, plus authentication/etc files"
   echo
   echo "./pghotbackup.sh db_host db_port backup_path"
   echo
   echo "Example:"
   echo "  /var/lib/pgsql/pghotbackup.sh rtp-apl-vpg 5432 /data/pg96/backups/rtp/"
   echo
   exit 0;
fi

if [ `whoami` != "postgres" ]; then
   echo "ERROR: This script must be run as the postgres o/s user."
   exit 1;
fi

#Connect to the vhost only to determine who the current DB primary is, then connect directly to that DB primary for the backup, thus bypassing PGPool.
DBHOST=`ssh $1 'for i in {0..2}; do pcp_node_info -w $i | grep "primary" | cut -d" " -f1; done'`
DBPORT=`ssh $1 'for i in {0..2}; do pcp_node_info -w $i | grep "primary" | cut -d" " -f2; done'`
BACKUPPATH="$3"
DIRNAME="$BACKUPPATH"/hotbackup_`date +\%a_\%Y\%m\%d_\%H\%M\%S`

echo; date "+%a_%Y-%m-%d_%H:%M:%S - START hot backup on $DBHOST:$DBPORT to $DIRNAME..."

# Run hot backup
/usr/bin/pg_basebackup -h $DBHOST -p $DBPORT -U postgres -D $DIRNAME -R -x -z --format=t

# Copy authentication files, config files, anything else that needs to be backed-up
scp $DBHOST:/etc/pgpool-II/pool_passwd   $DIRNAME/$DBHOST.pool_passwd
scp $DBHOST:/var/lib/pgsql/.pgpass       $DIRNAME/$DBHOST.pgpass
scp $DBHOST:/etc/pgpool-II/pgpool.conf   $DIRNAME/$DBHOST.pgpool.conf
scp $DBHOST:/etc/pgpool-II/pool_hba.conf $DIRNAME/$DBHOST.pool_hba.conf
scp $DBHOST:/etc/pgpool-II/pcp.conf $DIRNAME/$DBHOST.pcp.conf

echo; date "+%a_%Y-%m-%d_%H:%M:%S - FINISHED hot backup on $DBHOST:$DBPORT to $DIRNAME..."; echo

