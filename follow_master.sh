#!/usr/bin/bash +x
# This script is called by PGPool for each standby node after a failover.
# * %d  DB node ID of the detached node
# * %h  Hostname of the detached node
# * %p  Port number of the detached node
#  %D   Database cluster directory of the detached node
#  %M   Old master node ID
#  %m   New master node ID
#  %H   Hostname of the new master node
#  %P   Old primary node ID
#  %r   Port number of the new master node
#  %R   Database cluster directory of the new master node
#  %%   '%' character
# pgpool.conf: follow_master_command = '/etc/pgpool-II/follow_master.sh %d %h %p postgres'
# Log format: dbcluster, timestamp, promoted_node, failover_type
# Load log data like so: cat /var/lib/pgsql/.failover.log | psql -h rtp-dwh-vpg alm_custom_stats -c '\copy failover_data from STDIN;'
exec &>> /var/lib/pgsql/.failover.log

STANDBY_NODE=$1
STANDBY_HOST=$2
STANDBY_PORT=$2
DB_USER=$4
SSH_OPT='-q -o ConnectTimeout=1 -o ConnectionAttempts=30'
THIS_HOST=`hostname`
NUMBER_OF_NODES=`pcp_node_count -w`
dbcluster=`cat /var/lib/pgsql/.virtual_hostname`

printf "$dbcluster, `date +'%F %T %Z'`, $STANDBY_HOST, DB Standby Auto-Recovery Started\n"

# The objective is to get the cluster back to an HA state (at least 1 standby up) as quickly as reasonably possible.
# If there are multiple standby's and 1 is inaccessible, the other accessible standby's will have to wait for it to timeout, so skip it.
# If there's only one standby, then let it retry the default 30 times since it's not blocking another standby from recovery.
if [ "$NUMBER_OF_NODES" -gt "2" ]; then      #More than 1 standby, skip current one if not accessible by ssh
   ssh $SSH_OPT $STANDBY_HOST ":"            #try to get ssh connection but do nothing
   if [ "$?" -eq "0" ]; then                 #If it's accessible, then recover it
      sleep 10; pcp_recovery_node -w -v -n $STANDBY_NODE > /dev/null
   fi
elif [ "$NUMBER_OF_NODES" -eq "2" ]; then    #Only 1 standby, use pcp_recovery_node with default retry whether it's accessible or not.
   sleep 10; pcp_recovery_node -w -v -n $STANDBY_NODE > /dev/null
fi

printf "$dbcluster, `date +'%F %T %Z'`, $STANDBY_HOST, DB Standby Auto-Recovery Completed\n"
