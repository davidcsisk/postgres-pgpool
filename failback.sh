#!/bin/sh
# Execute failback operations.
# special values:  %d = rejoining node id
#                  %h = rejoining host name
#                  %p = rejoining port number
#                     %D = rejoining database cluster path
#                     %M = old master node id
#                     %m = new master node id
#                     %H = new master node host name
#                     %P = Current primary node id
#                     %r = new master port number
#                     %R = new master database cluster path
#                     %N = old primary node hostname
#                     %S = old primary node port number
#                     %% = '%' character
#
# Called by PGPool as specified in pgpool.conf:
# failback_command = '/etc/pgpool-II/failback.sh %d %h %p'
# Log format: dbcluster, timestamp, promoted_node, failover_type
# Load log data like so: cat /var/lib/pgsql/.failover.log | psql -h rtp-dwh-vpg alm_custom_stats -c '\copy failover_data from STDIN;'
exec &>> /var/lib/pgsql/.failover.log

rejoin_node=$1
rejoin_host=$2
rejoin_port=$3

set_sync_state () {
   standby_names="'FIRST 1 ($backslash\"$1$backslash\")'"
   sedcmd="sed -i \"s/.*synchronous_standby_names =.*/synchronous_standby_names = $standby_names/\" /var/lib/pgsql/10/data/postgresql.conf"
   ssh -q $primary_hostname bash << _EOF_
       $sedcmd
       source /var/lib/pgsql/.bash_profile
       pg_ctl reload
_EOF_
   printf "$dbcluster, `date +'%F %T %Z'`, $1, DB Standby set to synchronous\n"
}

node0_hostname=`pcp_node_info -w 0 | awk -F[" "] '{print $1}'`
node1_hostname=`pcp_node_info -w 1 | awk -F[" "] '{print $1}'`
node2_hostname=`pcp_node_info -w 2 | awk -F[" "] '{print $1}'`
node0_role=`pcp_node_info -w 0 | awk -F[" "] '{print $6}'`
node1_role=`pcp_node_info -w 1 | awk -F[" "] '{print $6}'`
node2_role=`pcp_node_info -w 2 | awk -F[" "] '{print $6}'`
node0_status=`pcp_node_info -w 0 | awk -F[" "] '{print $5}'`
node1_status=`pcp_node_info -w 1 | awk -F[" "] '{print $5}'`
node2_status=`pcp_node_info -w 2 | awk -F[" "] '{print $5}'`

primary_hostname=`for i in {0..2}; do pcp_node_info -w $i | grep 'primary' | awk -F[" "] '{print $1}'; done`

backslash='\'
source /var/lib/pgsql/.bash_profile
dbcluster=`cat /var/lib/pgsql/.virtual_hostname`

rep_count=`echo "SELECT count(*) FROM pg_stat_wal_receiver WHERE status = 'streaming';" | env PGCONNECT_TIMEOUT=5 psql -qtA -h $rejoin_host -p $rejoin_port`

# Determine if the attached node is not replicating and should be immediately detached
if [ "$?" -eq "2" ]; then #ERROR, catch exit status 2 from timeout if something goes wrong with the check
   pcp_detach_node -w $rejoin_node
   printf "$dbcluster, `date +'%F %T %Z'`, $rejoin_host, DB Standby Re-attach Failed (Replication check timeout)\n"
   exit 1;
elif [ "$rep_count" -eq "0" ]; then  #ERROR, rejoining node is not replicating...detach the node.
   pcp_detach_node -w $rejoin_node
   printf "$dbcluster, `date +'%F %T %Z'`, $rejoin_host, DB Standby Re-attach Failed (Standby not replicating)\n"
   exit 1;
elif [ "$rep_count" -eq "1" ]; then  #SUCCESS, rejoining node is replicating...allow attach, and proceed to synchronous replication settings.
   printf "$dbcluster, `date +'%F %T %Z'`, $rejoin_host, DB Standby Re-attach Succeeded (Replication active)\n"
else #ERROR, unable to determine replication status...detach the node.
   pcp_detach_node -w $rejoin_node
   printf "$dbcluster, `date +'%F %T %Z'`, $rejoin_host, DB Standby Re-attach Failed (Replication check indeterminant)\n"
   exit 1;
fi

# Handle synchronous replication
if [ "$node0_role" == "primary" ]; then
   if [ "$node1_status" == "up" -o "$node1_status" == "waiting" ]; then  #make this node sync standby
      set_sync_state $node1_hostname
   elif [ "$node1_status" == "down" -a "$node2_status" == "up" -o "$node1_status" == "down" -a "$node2_status" == "waiting" ]; then  #make next node sync
      set_sync_state $node2_hostname
   fi
elif [ "$node1_role" == "primary" ]; then
   if [ "$node0_status" == "up" -o "$node0_status" == "waiting" ]; then  #make this node sync standby
      set_sync_state $node0_hostname
   elif [ "$node0_status" == "down" -a "$node2_status" == "up" -o "$node0_status" == "down" -a "$node2_status" == "waiting" ]; then  #make next node sync
      standby_names="'FIRST 1 ($backslash\"$node2_hostname$backslash\")'"
      set_sync_state $node2_hostname
   fi
elif [ "$node2_role" == "primary" ]; then
   if [ "$node0_status" == "up" -o "$node0_status" == "waiting" ]; then  #make this node sync standby
      set_sync_state $node0_hostname
   elif [ "$node0_status" == "down" -a "$node1_status" == "up" -o "$node0_status" == "down" -a "$node1_status" == "waiting" ]; then  #make next node sync
      set_sync_state $node1_hostname
   fi
fi
exit 0;

