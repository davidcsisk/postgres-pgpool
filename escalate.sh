#! /bin/bash
# Execute escalate/de-escalate post actionss.
#
# Called by PGPool as specified in pgpool.conf:
# wd_escalation_command = '/etc/pgpool-II/escalate.sh -e'
# wd_de_escalation_command = '/etc/pgpool-II/escalate.sh -d'
# Log format: dbcluster, timestamp, promoted_node, failover_type
# Load log data like so: cat /var/lib/pgsql/.failover.log | psql -h rtp-dwh-vpg alm_custom_stats -c '\copy failover_data from STDIN;'
exec &>> /var/lib/pgsql/.failover.log

action=$1
source /var/lib/pgsql/.bash_profile
dbcluster=`cat /var/lib/pgsql/.virtual_hostname`

if [ "$action" == "-e" ]; then   # Post escalate action
   date "+$dbcluster, %F %T %Z, $HOSTNAME, PGPool Master Promoted"
elif [ "$action" == "-d" ]; then   # Post de-escalate action 
   date "+$dbcluster, %F %T %Z, $HOSTNAME, PGPool Master Demoted"
fi

exit 0;
