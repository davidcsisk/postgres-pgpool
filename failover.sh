#! /bin/sh
# Execute failover v2.0
# special values:  %d = Falling node id
#                  %h = Falling node hostname
#                  %p = Falling node port number
#                       %D = Falling database cluster path
#                       %m = new master node id
#                       %M = old master node id
#                  %H = new master node host name
#                  %P = old primary node id
#                  %R = new master database cluster path
#                  %r = new master port number
#                       %N = Old primary hostname
#                       %S = Old primary port number
#                       %% = '%' character
#
# Called by PGPool as specified in pgpool.conf:
# failover_command = '/etc/pgpool-II/failover.sh %d %h %p %P %H %R %r'
# Log format: dbcluster, timestamp, promoted_node, failover_type
# Load log data like so: cat /var/lib/pgsql/.failover.log | psql -h rtp-dwh-vpg alm_custom_stats -c '\copy failover_data from STDIN;'
exec &>> /var/lib/pgsql/.failover.log

falling_nodeid=$1          # %d
falling_host=$2            # %h
falling_port=$3            # %p
old_primary_nodeid=$4      # %P
new_primary_host=$5        # %H
new_primary_pgdata=$6      # %R
new_primary_port=$7        # %r

current_primary_hostname=`for i in {0..2}; do pcp_node_info -w $i | grep ' primary ' | awk -F[" "] '{print $1}'; done`
sync_standby_hostname=`for i in {0..2}; do pcp_node_info -w $i | grep ' sync ' | awk -F[" "] '{print $1}'; done`
async_standby_hostname=`for i in {0..2}; do pcp_node_info -w $i | grep ' async ' | awk -F[" "] '{print $1}'; done`

source /var/lib/pgsql/.bash_profile
backslash='\'
dbcluster=`cat /var/lib/pgsql/.virtual_hostname`

if [ $falling_nodeid = $old_primary_nodeid ]; then
    IS_REMOTE_DR=`ssh -qT postgres@$new_primary_host 'source ~/.bash_profile; echo $REMOTE_DR'`
    if [ "$IS_REMOTE_DR" == "Y" ]; then
       printf "$dbcluster, `date +'%F %T %Z'`, $new_primary_host, Remote DR - no DB Primary Available\n"
       exit 1;
    fi
    ssh -qT postgres@$new_primary_host "source ~/.bash_profile; pg_ctl promote -D $new_primary_pgdata > /dev/null"
    ssh -qT postgres@$new_primary_host psql -q -p $new_primary_port -c 'checkpoint;'
    sedcmd="sed -i \"s/.*synchronous_standby_names =.*/synchronous_standby_names = ''/\" /var/lib/pgsql/10/data/postgresql.conf"
    ssh -q $new_primary_host bash << _EOF_
       source /var/lib/pgsql/.bash_profile
       $sedcmd
       pg_ctl reload > /dev/null
_EOF_
    printf "$dbcluster, `date +'%F %T %Z'`, $new_primary_host, DB Primary Promoted\n"
else
    rep_count=`for i in {0..2}; do pcp_node_info -w $i | grep 'up' | grep 'standby' | awk -F[" "] '{print $1}'; done | wc -l`
    if [ "$rep_count" -eq "0" ]; then  #No standby's are up
       sedcmd="sed -i \"s/.*synchronous_standby_names =.*/synchronous_standby_names = ''/\" /var/lib/pgsql/10/data/postgresql.conf"
       ssh -q $new_primary_host bash << _EOF_
          source /var/lib/pgsql/.bash_profile
          $sedcmd
          pg_ctl reload > /dev/null
_EOF_
    elif [ "$rep_count" -eq "1" ]; then  #One standby is up
       # NOTE: For some reason, when the current primary is node 2 in this case, PGPool passes in the wrong new_primary_host, so I am using the 
       #       current primary hostname as captured from the pcp_node_info utility.
       # Determine if synchronous standby is the falling host
       if [ "$falling_host" ==  "$sync_standby_hostname" ]; then
          # update standby_synchronous_names to asynchronous standby and reload 
          standby_names=`echo "'FIRST 1 ($standby_names$backslash\"$async_standby_hostname$backslash\")'"`
          sedcmd="sed -i \"s/.*synchronous_standby_names =.*/synchronous_standby_names = $standby_names/\" /var/lib/pgsql/10/data/postgresql.conf"
          ssh -q $current_primary_hostname bash << _EOF_
              source /var/lib/pgsql/.bash_profile
              $sedcmd
              pg_ctl reload > /dev/null
_EOF_
       fi
    fi
    printf "$dbcluster, `date +'%F %T %Z'`, $falling_nodeid, DB Standby Downed\n"
fi
exit 0
