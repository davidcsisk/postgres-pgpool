#!/bin/bash
# Define variables
RED='\033[0;41;30m'
STD='\033[0;0;39m'

node0_host=`cat /etc/pgpool-II/pgpool.conf | grep backend_hostname0 | cut -d"'" -f2`
node1_host=`cat /etc/pgpool-II/pgpool.conf | grep backend_hostname1 | cut -d"'" -f2`
node2_host=`cat /etc/pgpool-II/pgpool.conf | grep backend_hostname2 | cut -d"'" -f2`
 
# User defined functions
pause(){
  read -p "Press [Enter] key to continue..." fackEnterKey
}

recover_down_standby_manual(){
        read -p "Enter standby node_id to recover: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID` && NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'` && NODE_PORT=`echo $OUTPUT | awk '{print $2}'`
        NODE_STATUS=`echo $OUTPUT | awk '{print $3}'`
        IS_STANDBY=`psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c "select count(*) from pg_stat_wal_receiver where status='streaming';"`
        if [ "$IS_STANDBY" -eq "0" ]; then
           echo
           echo "WARNING: Node $NODE_ID host $NODE_HOSTNAME appears to be a PRIMARY or PROMOTED STANDBY."
           read -p "Press [Enter] key to continue, or CTRL-C to abort..." fackEnterKey
           echo
        elif [ "$IS_STANDBY" -eq "1" ]; then
           echo
           echo "Node $NODE_ID host $NODE_HOSTNAME appears to be a replicating STANDBY...proceeding."
           echo
        else
           echo
           echo "WARNING: Could not determine status of node $NODE_ID host $NODE_HOSTNAME."
           read -p "Press [Enter] key to continue, or CTRL-C to abort..." fackEnterKey
           echo
        fi
        if [ "$NODE_STATUS" -eq "2" ]; then
           echo
           echo "Node $NODE_ID host $NODE_HOSTNAME does not appear to be down...detach the node, then retry recovery."
           echo
        else
           echo
           read -p "Enter node_id for PRIMARY node: " SOURCENODE_ID
           OUTPUT=`pcp_node_info -w $SOURCENODE_ID`
           SOURCENODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'`
           SOURCENODE_PORT=`echo $OUTPUT | awk '{print $2}'`
           echo "A hot backup of the source node will be executed...this may take several moments. Confirm the following info is correct:"
           echo
           echo "CONFIRM: Recover node $NODE_ID $NODE_HOSTNAME:$NODE_PORT using primary node $SOURCENODE_ID $SOURCENODE_HOSTNAME:$SOURCENODE_PORT"
           echo
           read -p "Press [Enter] key to continue if correct, or CTRL-C to abort..." fackEnterKey
           echo
           ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pg_ctl stop -m fast"
           echo "Clearing the data directory on $NODE_HOSTNAME..."
           ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && rm -rf $PGDATA/*"
           echo "Executing hot backup of source node..."
           ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pg_basebackup -h $SOURCENODE_HOSTNAME -p $SOURCENODE_PORT -U postgres -D $PGDATA -R"
           ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pg_ctl start -l /dev/null"
           sleep 10
           LOGNAME=`ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && ls -t $PGDATA/pg_log/ | head -n 1"`
           ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && tail -n 20 $PGDATA/pg_log/$LOGNAME"
           IS_STANDBY=`psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c "select count(*) from pg_stat_wal_receiver where status='streaming';"`
           echo
           if [ "$IS_STANDBY" -eq "1" ]; then
              echo "Standby node $NODE_ID host $NODE_HOSTNAME is recovered and streaming replication activated...re-attaching standby node $NODE_ID."
              pcp_attach_node -w $NODE_ID
           else
              echo "Standby node $NODE_ID host $NODE_HOSTNAME is recovered but may not be up or replicating yet...skipping re-attach."
              echo "Confirm the node is up and replicating, then attach using the A(ttach) menu option."
           fi
        fi
        pause
}

recover_down_standby_pcprecoverynode(){
        read -p "Enter standby node_id to recover via pcp_recovery_node: " NODE_ID
        pcp_recovery_node -w -n $NODE_ID
        pause
}

attach_node(){
        read -p "Enter node_id to ATTACH: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID` && NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'` && NODE_PORT=`echo $OUTPUT | awk '{print $2}'`
        IS_STANDBY=`psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c "select count(*) from pg_stat_wal_receiver where status='streaming';"`
        if [ "$IS_STANDBY" -eq "1" ]; then
           echo
           echo "Node $NODE_ID host $NODE_HOSTNAME appears to be a replicating STANDBY...proceeding with ATTACH."
           echo
           echo "Re-attaching node $NODE_ID hostname $NODE_HOSTNAME"
           pcp_attach_node -w $NODE_ID
        else
           echo "Node $NODE_ID host $NODE_HOSTNAME does not appear to be a replicating STANDBY...troubleshoot and retry attach."
        fi
        pause
}
 
detach_node(){
        read -p "Enter node_id to DETACH: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID` && NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'` && NODE_PORT=`echo $OUTPUT | awk '{print $2}'`
        IS_STANDBY=`psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c "select count(*) from pg_stat_wal_receiver where status ='streaming';"`
        if [ "$IS_STANDBY" -eq "1" ]; then
           echo
           echo "Detaching standby node $NODE_ID hostname $NODE_HOSTNAME"
           echo
           pcp_detach_node -w $NODE_ID
        elif [ "$IS_STANDBY" -eq "0" ]; then
           echo
           echo "Detaching node $NODE_ID hostname $NODE_HOSTNAME"
           echo "WARNING: the node being detached appears to be a PRIMARY, this action will trigger a failover"
           echo
           read -p "Press [Enter] key to continue if correct, or CTRL-C to abort..." fackEnterKey
           pcp_detach_node -w $NODE_ID
        else
           echo
           echo "Detaching  node $NODE_ID hostname $NODE_HOSTNAME"
           echo "WARNING: status of the the node being detached could not be determined, this action could trigger a failover"
           echo
           read -p "Press [Enter] key to continue if correct, or CTRL-C to abort..." fackEnterKey
           pcp_detach_node -w $NODE_ID
        fi
        pause
}

check_pg_status() {
        read -p "Enter node_id to check POSTGRES: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID`
        NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'`
        NODE_PORT=`echo $OUTPUT | awk '{print $2}'`
        echo
        echo "NODE: $NODE_HOSTNAME:$NODE_PORT"
        ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pg_ctl status"
        echo
        if [ `psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c 'select count(*) from pg_stat_replication;'` -gt 0 ]; then
           echo "Node is DB primary...connected DB standby's:"
           psql -h $NODE_HOSTNAME -p $NODE_PORT -c 'select pid,application_name,client_addr,client_hostname,state,sync_state from pg_stat_replication;'
        elif [ `psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c 'select count(*) from pg_stat_wal_receiver;'` -gt 0 ]; then
           echo "Node is a DB standby...connected DB primary:"
           psql -h $NODE_HOSTNAME -p $NODE_PORT -c "select pid, substring(conninfo for position('fallback' in conninfo)-1) from pg_stat_wal_receiver;"
        else
           echo "Could not determine node role"
        fi
        echo
#        echo "SR and Backup processes on node $NODE_ID - $NODE_HOSTNAME:"
#        echo "----------------------------------------------------------"
#        ssh -q $NODE_HOSTNAME 'pgrep -flu postgres stream'
#        ssh -q $NODE_HOSTNAME 'pgrep -flu postgres pg_basebackup'
#        echo
        pause
}
 
start_postgres(){
        read -p "Enter node_id to start POSTGRES: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID`
        NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'`
        NODE_PORT=`echo $OUTPUT | awk '{print $2}'`
        NODE_STATUS=`echo $OUTPUT | awk '{print $3}'`
        ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pg_ctl start -l /dev/null"
        sleep 10
        LOGNAME=`ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && ls -t $PGDATA/pg_log/ | head -n 1"`
        ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && tail -n 20 $PGDATA/pg_log/$LOGNAME"
        IS_STANDBY=`psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c "select count(*) from pg_stat_wal_receiver where status='streaming';"`
        if [ "$IS_STANDBY" -eq "0" ]; then
           echo
           echo "WARNING: Node $NODE_ID host $NODE_HOSTNAME appears to be a PRIMARY or PROMOTED STANDBY."
           echo
        elif [ "$IS_STANDBY" -gt "0" ]; then
           echo
           echo "WARNING: Node $NODE_ID host $NODE_HOSTNAME appears to be a STANDBY that's not replicating."
           echo
        elif [ "$IS_STANDBY" -eq "1" ]; then
           echo
           echo "Node $NODE_ID host $NODE_HOSTNAME appears to be a replicating STANDBY."
           echo
        else
           echo
           echo "WARNING: Could not determine replication status of node $NODE_ID host $NODE_HOSTNAME."
           echo
        fi
        echo "If there appear to be no errors in the above output, then attach the recovered standby node"
        echo
        pause
}

stop_postgres(){
        read -p "Enter node_id to stop POSTGRES: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID`
        NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'`
        NODE_PORT=`echo $OUTPUT | awk '{print $2}'`
        NODE_STATUS=`echo $OUTPUT | awk '{print $3}'`
        IS_STANDBY=`psql -At -h $NODE_HOSTNAME -p $NODE_PORT -c "select count(*) from pg_stat_wal_receiver where status='streaming';"`
        if [ "$IS_STANDBY" -eq "0" ]; then
           echo
           echo "WARNING: Node $NODE_ID host $NODE_HOSTNAME appears to be a PRIMARY or PROMOTED STANDBY."
           read -p "Press [Enter] key to continue, or CTRL-C to abort..." fackEnterKey
           echo
        fi
        echo
        echo "CONFIRM: STOP postgres on node $NODE_ID $NODE_HOSTNAME:$NODE_PORT"
        echo
        read -p "Press [Enter] key to continue, or CTRL-C to abort..." fackEnterKey
        echo
        ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pg_ctl stop -m fast"
        LOGNAME=`ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && ls -t $PGDATA/pg_log/ | head -n 1"`
        ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && tail -n 20 $PGDATA/pg_log/$LOGNAME"
        pause
}

less_pg_log() {
        read -p "Enter node_id to less Postgres log: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID`
        NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'`
        LOGNAME=`ssh -q $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && ls -t $PGDATA/pg_log/ | head -n 1"`
        ssh -q -t $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && less +G $PGDATA/pg_log/$LOGNAME"
}

less_pool_log() {
        read -p "Enter node_id to less PGPool log: " NODE_ID
        OUTPUT=`pcp_node_info -w $NODE_ID`
        NODE_HOSTNAME=`echo $OUTPUT | awk '{print $1}'`
        ssh -q -t $NODE_HOSTNAME "less +G /var/log/pgpool.log"
}

start_pgpool_node() {
        read -p "Enter node_id to start PGPool proxy instance: " NODE_ID
        if [ "$NODE_ID" -eq "0" ]; then NODE_HOSTNAME="$node0_host"; fi
        if [ "$NODE_ID" -eq "1" ]; then NODE_HOSTNAME="$node1_host"; fi
        if [ "$NODE_ID" -eq "2" ]; then NODE_HOSTNAME="$node2_host"; fi
        ssh -qt $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pgpool"
}

stop_pgpool_node() {
        read -p "Enter node_id to stop PGPool proxy instance: " NODE_ID
        if [ "$NODE_ID" -eq "0" ]; then NODE_HOSTNAME="$node0_host"; fi
        if [ "$NODE_ID" -eq "1" ]; then NODE_HOSTNAME="$node1_host"; fi
        if [ "$NODE_ID" -eq "2" ]; then NODE_HOSTNAME="$node2_host"; fi
        ssh -qt $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
}

restart_all_pgpool() {
        echo "Restart all PGPool proxies...this will result in a short outage"
        read -p "Press [Enter] key to continue, or CTRL-C to abort..." fackEnterKey
        ssh -qt $node0_host "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
        ssh -qt $node1_host "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
        ssh -qt $node2_host "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
        ssh -qt $node2_host "source /var/lib/pgsql/.bash_profile && pgpool -D"
        ssh -qt $node1_host "source /var/lib/pgsql/.bash_profile && pgpool -D"
        ssh -qt $node0_host "source /var/lib/pgsql/.bash_profile && pgpool -D"
}

start_all_services() {
        echo "Starting all Postgres and PGPool services in this cluster"
        ssh -qt $node0_host "source /var/lib/pgsql/.bash_profile && pg_ctl start"
        ssh -qt $node1_host "source /var/lib/pgsql/.bash_profile && pg_ctl start"
        ssh -qt $node2_host "source /var/lib/pgsql/.bash_profile && pg_ctl start"
        ssh -qt $node2_host "source /var/lib/pgsql/.bash_profile && pgpool -D"
        ssh -qt $node1_host "source /var/lib/pgsql/.bash_profile && pgpool -D"
        ssh -qt $node0_host "source /var/lib/pgsql/.bash_profile && pgpool -D"
}

stop_all_services() {
        echo "Stopping all Postgres and PGPool services in this cluster"
        read -p "Press [Enter] key to continue, or CTRL-C to abort..." fackEnterKey
        ssh -qt $node0_host "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
        ssh -qt $node1_host "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
        ssh -qt $node2_host "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
        ssh -qt $node2_host "source /var/lib/pgsql/.bash_profile && pg_ctl stop -m fast"
        ssh -qt $node1_host "source /var/lib/pgsql/.bash_profile && pg_ctl stop -m fast"
        ssh -qt $node0_host "source /var/lib/pgsql/.bash_profile && pg_ctl stop -m fast"
}

kill_pgpool_node() {
        read -p "Enter node hostname to kill/cleanup PGPool instance: " NODE_HOSTNAME
        ssh -qt $NODE_HOSTNAME "source /var/lib/pgsql/.bash_profile && pkill -9 pgpool; rm -rf /tmp/.s.PGSQL.5432 /tmp/.s.PGSQL.9898"
}


connected_db_sessions() {
        echo
        echo "Connected DB session counts:"
        echo
        psql -h localhost -p 5432 -c 'select a.datname, a.usename, a.client_addr, a.state, s.ssl, count(*) from pg_stat_activity a join pg_stat_ssl s on (a.pid = s.pid) group by 1,2,3,4,5;'
        pause
}

connected_pgpool_sessions() {
        echo
        read -p "Enter l(ist unique IP's) or d(etailed connection list): " RESPONSE
        if [ "$RESPONSE" == "l" ]; then
           echo; echo "IP addresses connected to local PGPool instance:"
           ps aux | grep pgpool | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | sort -u
           echo; pause
        elif [ "$RESPONSE" == "d" ]; then
           read -p "Enter string to filter on or press ENTER for all results: " RESPONSE
           echo; echo "Details of connections to local PGPool instance:"
           ps aux | grep pgpool | grep -E "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep "$RESPONSE"
           echo; pause
        fi
}


# Display menu
show_menus() {
	clear
        env PGCONNECT_TIMEOUT=1 psql -h localhost -p 5432 -c 'show pool_nodes;' > /dev/null

        node0_dbstatus=`pcp_node_info -w 0 | awk -F[" "] '{print $5}'`
        node1_dbstatus=`pcp_node_info -w 1 | awk -F[" "] '{print $5}'`
        node2_dbstatus=`pcp_node_info -w 2 | awk -F[" "] '{print $5}'`

        node0_dbrole=`pcp_node_info -w 0 | awk -F[" "] '{print $6}'`
        node1_dbrole=`pcp_node_info -w 1 | awk -F[" "] '{print $6}'`
        node2_dbrole=`pcp_node_info -w 2 | awk -F[" "] '{print $6}'`

        node0_repstate=`pcp_node_info -w 0 | awk -F[" "] '{print $8}'`
        node1_repstate=`pcp_node_info -w 1 | awk -F[" "] '{print $8}'`
        node2_repstate=`pcp_node_info -w 2 | awk -F[" "] '{print $8}'`

        node0_syncstate=`pcp_node_info -w 0 | awk -F[" "] '{print $9}'`
        node1_syncstate=`pcp_node_info -w 1 | awk -F[" "] '{print $9}'`
        node2_syncstate=`pcp_node_info -w 2 | awk -F[" "] '{print $9}'`

        node0_proxystate=`pcp_watchdog_info -w | tail -n 3 | grep $node0_host | awk -F[" "] '{print $8}'`
        node1_proxystate=`pcp_watchdog_info -w | tail -n 3 | grep $node1_host | awk -F[" "] '{print $8}'`
        node2_proxystate=`pcp_watchdog_info -w | tail -n 3 | grep $node2_host | awk -F[" "] '{print $8}'`

	echo "============================================================================================================================================="
        echo "PG10/PGPool4.1 Cluster: vhost $VHOST | host `hostname` | Date:`date` |  IP's: `hostname -I`"
	echo "============================================================================================================================================="
        echo "Node	Host		DB Status	DB Role		Proxy state	Replication State	Synchronous State"
        echo "----	----		--------	-------		-----------	-----------------	-----------------"
        echo "0	$node0_host	$node0_dbstatus		$node0_dbrole		$node0_proxystate		$node0_repstate		$node0_syncstate"
        echo "1	$node1_host	$node1_dbstatus		$node1_dbrole		$node1_proxystate		$node1_repstate		$node1_syncstate"
        echo "2	$node2_host	$node2_dbstatus		$node2_dbrole		$node2_proxystate		$node2_repstate		$node2_syncstate"
        echo
        ps aux | grep -i pcp_reco | grep -v grep
        if [ "$?" -eq "0" ]; then echo "NOTICE: One or more nodes currently in process of auto-recovery"; echo; fi
	echo "============================================"	
	echo " Postgres/PGPool Cluster Control Menu v2.0.0"
	echo "============================================"
	echo "<ENTER>  Re-query Cluster State"
        echo
	echo "a                Attach node"
	echo "D                Detach node"
	echo "r                Recover down standby node using pcp_recovery_node"
	echo "R                Recover down standby node from primary using pg_basebackup"
	echo "startdb          Start Postgres on node"
	echo "startpgpool      Start PGPool on node"
	echo "stopdb           Stop Postgres on node"
	echo "stoppgpool       Stop PGPool on node"
	echo "restartallpgpool Restart all PGPool proxies"
	echo "startallservices Start all Postgres and PGPool instances"
	echo "stopallservices  Stop all PGPool and Postgres instances"
	echo "c                Check Postgres and Streaming Replication on node"
	echo "s                Show connected DB sessions"
	echo "S                Show connected PGPool sessions"
	echo "l                Less latest Postgres log on node (q to exit less)"
	echo "L                Less latest PGPool log on node (q to exit less)"
	echo "x                Exit"
        echo
}

# read input from the keyboard and take a action
read_options(){
	local choice
	read -p "Enter choice: " choice
	case $choice in
		a) attach_node ;;
		D) detach_node ;;
		r) recover_down_standby_pcprecoverynode ;;
		R) recover_down_standby_manual ;;
		startdb) start_postgres ;;
		stopdb) stop_postgres ;;
		startpgpool) start_pgpool_node ;;
		stoppgpool) stop_pgpool_node ;;
		restartallpgpool) restart_all_pgpool ;;
		startallservices) start_all_services ;;
		stopallservices) stop_all_services ;;
		c) check_pg_status ;;
		s) connected_db_sessions ;;
		S) connected_pgpool_sessions ;;
		l) less_pg_log ;;
		L) less_pool_log ;;
		x) echo && exit 0;;
		*) show_menus;;
	esac
}

# Trap CTRL+C, CTRL+Z and quit singles
#trap '' SIGINT SIGQUIT SIGTSTP
trap '' SIGQUIT SIGTSTP

VHOST=`cat /var/lib/pgsql/.virtual_hostname`

# Main logic - infinite loop
while true
do
     show_menus
     read_options
done

