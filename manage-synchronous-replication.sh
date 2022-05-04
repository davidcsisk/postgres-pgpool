#!/bin/sh

ACTION="$1"
direct_port=5493
backslash='\'

# Find the DB primary
cluster_hosts=`cat /etc/pgpool-II/pgpool.conf | grep backend_hostname | sed "s/backend_hostname.*= // " | sed "s/'//g"`
for cluster_host in $cluster_hosts; do
    rep_count=`echo "SELECT count(*) FROM pg_stat_replication;" | env PGCONNECT_TIMEOUT=5 psql -qtA -h $cluster_host -p $direct_port`
   if [ "$rep_count" -ge "1" ]; then
      primary_host=$cluster_host
   fi
done
 
if [ -z $1 ] || [ $1 == '--help' ] || [ $1 == '-h' ] ; then
   echo "Version 1.0"
   echo "Usage: Use to show and modify Synchronous Replication state in local DB cluster"
   echo ""
   echo "./manage-synchronous-replication.sh --sync (Put DB Primary into Synchronous Replication mode.)"
   echo "./manage-synchronous-replication.sh --async (Take DB Primary out of Synchronous Replication mode)"
   echo ""
   echo "Current cluster hosts:" $cluster_hosts
   echo "Current DB primary: $primary_host"; echo
   psql -h $primary_host -p 5493 -c 'show synchronous_standby_names;'
   psql -h $primary_host -p 5493 -c 'select * from pg_stat_replication;'
   exit 0;
fi

if [ $ACTION == '--sync' ] ; then
   standby_names="'FIRST 1 ("
   for cluster_host in $cluster_hosts; do
     if [ "$cluster_host" != "$primary_host" ]; then
        standby_names=`echo "$standby_names$backslash\"$cluster_host$backslash\"," | sed 's/^,//'`
     fi
   done
   standby_names=`echo "$standby_names" | sed "s/,$/)'/"` # output of this block = 'FIRST 1 (\"hostname1\",\"hostname2\")'
   sedcmd="sed -i \"s/.*synchronous_standby_names =.*/synchronous_standby_names = $standby_names/\" /var/lib/pgsql/10/data/postgresql.conf"
   echo $sedcmd
   ssh -q $primary_host bash << _EOF_
      source /var/lib/pgsql/.bash_profile
      $sedcmd
      pg_ctl reload
_EOF_
   psql -h $primary_host -p 5493 -c 'show synchronous_standby_names;'
   psql -h $primary_host -p 5493 -c 'select * from pg_stat_replication;'
fi

if [ $ACTION == '--async' ] ; then
   sedcmd="sed -i \"s/.*synchronous_standby_names =.*/synchronous_standby_names = ''/\" /var/lib/pgsql/10/data/postgresql.conf"
   ssh -q $primary_host bash << _EOF_
      source /var/lib/pgsql/.bash_profile
      $sedcmd
      pg_ctl reload
_EOF_
   psql -h $primary_host -p 5493 -c 'show synchronous_standby_names;'
   psql -h $primary_host -p 5493 -c 'select * from pg_stat_replication;'
fi

exit 0;
