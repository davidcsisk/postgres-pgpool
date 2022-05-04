#!/usr/bin/bash

CFGFILE="/etc/pgpool-II/pgpool.conf"
PARMFILE=".pgpool_config.parm"

if [ "$1" == '--help' ] || [ "$1" == '-h' ] ; then
   echo "Version 1.0"
   echo "Usage: Run this script on each PostgreSQL/PGPool node to configure PGPool HA."
   echo "       If a parameter file has not been created, this script will create one, then notify you to fill out the details and re-run."
   exit 0;
fi

if [ ! -f ""$PARMFILE"" ]; then
   echo '#DB/Proxy nodes' > "$PARMFILE"
   echo '#nodeid:hostname_or_ip[:nodb]' >> "$PARMFILE"
   echo '0:' >> "$PARMFILE"
   echo '1:' >> "$PARMFILE"
   echo '2:' >> "$PARMFILE"
   echo '' >> "$PARMFILE"
   echo '#Virtual host' >> "$PARMFILE"
   echo '#v:hostname:virtualIP' >> "$PARMFILE"
   echo 'v:' >> "$PARMFILE"
   echo '' >> "$PARMFILE"
   echo '#Load balancing' >> "$PARMFILE"
   echo 'lb:OFF' >> "$PARMFILE"
   echo '' >> "$PARMFILE"
   echo
   echo 'Parameter file did not exist...template created. Fill in the details, then re-run this script.'
   echo "Parameter file located here: "$PARMFILE""
   echo
   exit 1;
else
   if ! grep '#nodeid:hostname_or_ip\[:nodb]' .pgpool_config.parm > /dev/null; then
      sed -i 's/^#nodeid:hostname_or_ip/#nodeid:hostname_or_ip[:nodb]/' "$PARMFILE"
   fi
fi

# Get the parameter values from the parameter file
PARM_HOSTNAME0=`cat "$PARMFILE" | grep -v '#' | grep '^0:' | cut -d':' -f2`
PARM_OPTION0=`cat "$PARMFILE" | grep -v '#' | grep '^0:' | cut -d':' -f3`
PARM_HOSTNAME1=`cat "$PARMFILE" | grep -v '#' | grep '^1:' | cut -d':' -f2`
PARM_OPTION1=`cat "$PARMFILE" | grep -v '#' | grep '^1:' | cut -d':' -f3`
PARM_HOSTNAME2=`cat "$PARMFILE" | grep -v '#' | grep '^2:' | cut -d':' -f2`
PARM_OPTION2=`cat "$PARMFILE" | grep -v '#' | grep '^2:' | cut -d':' -f3`
PARM_HOSTNAME3=`cat "$PARMFILE" | grep -v '#' | grep '^3:' | cut -d':' -f2`
PARM_OPTION3=`cat "$PARMFILE" | grep -v '#' | grep '^3:' | cut -d':' -f3`
PARM_VHOSTNAME=`cat "$PARMFILE" | grep -v '#' | grep '^v:' | cut -d':' -f2`
PARM_VIRTUALIP=`cat "$PARMFILE" | grep -v '#' | grep '^v:' | cut -d':' -f3`
PARM_LOADBALANCE=`cat "$PARMFILE" | grep -v '#' | grep '^lb:' | cut -d':' -f2`
MYHOSTNAME=`hostname -s`

echo "$PARM_VHOSTNAME" > /var/lib/pgsql/.virtual_hostname

cat > "$CFGFILE" << '_EOF_'

### ALM On-Prem PGPool config parameters
# Static config parameters

listen_addresses = '*'
port = 5432
serialize_accept = on
num_init_children = 1048
max_pool = 1
listen_backlog_multiplier = 1
log_destination = 'syslog'
syslog_facility = 'LOCAL0'
syslog_ident = 'pgpool'
socket_dir = '/tmp'
pcp_listen_addresses = '*'
pcp_port = 9898
pcp_socket_dir = '/tmp'
pid_file_name = '/var/run/postgresql/pgpool.pid'
logdir = '/tmp'
connection_life_time = 300
connection_cache = OFF
enable_pool_hba = on
pool_passwd = 'pool_passwd'                             
authentication_timeout = 60
child_life_time = 300
client_idle_limit = 0
memory_cache_enabled = off

sr_check_user = 'postgres'
sr_check_password = 'p0$tgr3$'
sr_check_database = 'postgres'
sr_check_period = 10
delay_threshold = 1
log_standby_delay = 'if_over_threshold'

health_check_user = 'postgres' 
health_check_password = 'p0$tgr3$'
health_check_period = 1
health_check_timeout = 1
health_check_max_retries = 1      
health_check_retry_delay = 1    
connect_timeout = 800

master_slave_mode = on
master_slave_sub_mode = 'stream'

failover_command = '/etc/pgpool-II/failover.sh %d %P %H %R %r'
failback_command = '/etc/pgpool-II/failback.sh %d %h %p'
follow_master_command = '/etc/pgpool-II/follow_master.sh %d %h %p postgres'

recovery_user = 'postgres'
recovery_password = 'p0$tgr3$'
recovery_1st_stage_command = 'recovery_1st_stage.sh'
recovery_timeout = 5

ssl = ON
ssl_cert = '/etc/pgpool-II/server.crt'
ssl_key = '/etc/pgpool-II/server.key'
ssl_prefer_server_ciphers = ON
ssl_ciphers = 'HIGH:!MEDIUM:!LOW:!SSLv2:!SSLv3:!TLSv1:!TLSv1.1:+TLSv1.2:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA::DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA:!3DES'


use_watchdog = ON
fail_over_on_backend_error = false
failover_when_quorum_exists = on
failover_require_consensus = on
allow_multiple_failover_requests_from_node = ON
wd_port = 9000
wd_authkey = ''
wd_ipc_socket_dir = '/tmp'
wd_lifecheck_method = 'heartbeat'
wd_interval = 10
wd_heartbeat_port = 9694
wd_heartbeat_keepalive = 2
wd_heartbeat_deadtime = 15
heartbeat_destination_port0 = 9694
heartbeat_destination_port1 = 9694
other_wd_port0 = 9000
other_wd_port1 = 9000
other_pgpool_port0 = 5432
other_pgpool_port1 = 5432
wd_escalation_command = 'date "+%a_%Y-%m-%d_%H:%M:%S - PGPool master node Promoted" >> /var/lib/pgsql/.pgpool_ha.log'
wd_de_escalation_command = 'date "+%a_%Y-%m-%d_%H:%M:%S - PGPool master node Demoted" >> /var/lib/pgsql/.pgpool_ha.log'


if_cmd_path = '/etc/pgpool-II'
if_up_cmd = 'ip addr add $_IP_$/24 dev eth0 label eth0:0'
if_down_cmd = 'ip addr del $_IP_$/24 dev eth0'
arping_path = '/etc/pgpool-II'
arping_cmd = 'arping -U $_IP_$ -w 1'


# Host and Cluster specific parameters
_EOF_

# Postgres DB + PGPool node
if [ -n "$PARM_HOSTNAME0" -a -z "$PARM_OPTION0" ]; then echo "backend_hostname0 = '$PARM_HOSTNAME0'" >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a -z "$PARM_OPTION0" ]; then echo "backend_data_directory0 = '$PGDATA'"   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a -z "$PARM_OPTION0" ]; then echo "backend_port0 = 5493"                  >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a -z "$PARM_OPTION0" ]; then echo "backend_weight0 = 1"                   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a -z "$PARM_OPTION0" ]; then echo "backend_flag0 = 'ALLOW_TO_FAILOVER'"   >> "$CFGFILE"; fi

if [ -n "$PARM_HOSTNAME1" -a -z "$PARM_OPTION1" ]; then echo "backend_hostname1 = '$PARM_HOSTNAME1'" >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a -z "$PARM_OPTION1" ]; then echo "backend_data_directory1 = '$PGDATA'"   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a -z "$PARM_OPTION1" ]; then echo "backend_port1 = 5493"                  >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a -z "$PARM_OPTION1" ]; then echo "backend_weight1 = 1"                   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a -z "$PARM_OPTION1" ]; then echo "backend_flag1 = 'ALLOW_TO_FAILOVER'"   >> "$CFGFILE"; fi

if [ -n "$PARM_HOSTNAME2" -a -z "$PARM_OPTION2" ]; then echo "backend_hostname2 = '$PARM_HOSTNAME2'" >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a -z "$PARM_OPTION2" ]; then echo "backend_data_directory2 = '$PGDATA'"   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a -z "$PARM_OPTION2" ]; then echo "backend_port2 = 5493"                  >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a -z "$PARM_OPTION2" ]; then echo "backend_weight2 = 1"                   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a -z "$PARM_OPTION2" ]; then echo "backend_flag2 = 'ALLOW_TO_FAILOVER'"   >> "$CFGFILE"; fi

if [ -n "$PARM_HOSTNAME3" -a -z "$PARM_OPTION3" ]; then echo "backend_hostname3 = '$PARM_HOSTNAME3'" >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a -z "$PARM_OPTION3" ]; then echo "backend_data_directory3 = '$PGDATA'"   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a -z "$PARM_OPTION3" ]; then echo "backend_port3 = 5493"                  >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a -z "$PARM_OPTION3" ]; then echo "backend_weight3 = 1"                   >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a -z "$PARM_OPTION3" ]; then echo "backend_flag3 = 'ALLOW_TO_FAILOVER'"   >> "$CFGFILE"; fi

# DR Postgres DB
if [ -n "$PARM_HOSTNAME0" -a "$PARM_OPTION0" == "dr" ]; then echo "backend_hostname0 = '$PARM_HOSTNAME0'"    >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a "$PARM_OPTION0" == "dr" ]; then echo "backend_data_directory0 = '$PGDATA'"      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a "$PARM_OPTION0" == "dr" ]; then echo "backend_port0 = 5493"                     >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a "$PARM_OPTION0" == "dr" ]; then echo "backend_weight0 = 0"                      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME0" -a "$PARM_OPTION0" == "dr" ]; then echo "backend_flag0 = 'ALLOW_TO_FAILOVER'"      >> "$CFGFILE"; fi

if [ -n "$PARM_HOSTNAME1" -a "$PARM_OPTION1" == "dr" ]; then echo "backend_hostname1 = '$PARM_HOSTNAME1'"    >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a "$PARM_OPTION1" == "dr" ]; then echo "backend_data_directory1 = '$PGDATA'"      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a "$PARM_OPTION1" == "dr" ]; then echo "backend_port1 = 5493"                     >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a "$PARM_OPTION1" == "dr" ]; then echo "backend_weight1 = 0"                      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME1" -a "$PARM_OPTION1" == "dr" ]; then echo "backend_flag1 = 'ALLOW_TO_FAILOVER'"      >> "$CFGFILE"; fi

if [ -n "$PARM_HOSTNAME2" -a "$PARM_OPTION2" == "dr" ]; then echo "backend_hostname2 = '$PARM_HOSTNAME2'"    >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a "$PARM_OPTION2" == "dr" ]; then echo "backend_data_directory2 = '$PGDATA'"      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a "$PARM_OPTION2" == "dr" ]; then echo "backend_port2 = 5493"                     >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a "$PARM_OPTION2" == "dr" ]; then echo "backend_weight2 = 0"                      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME2" -a "$PARM_OPTION2" == "dr" ]; then echo "backend_flag2 = 'ALLOW_TO_FAILOVER'"      >> "$CFGFILE"; fi

if [ -n "$PARM_HOSTNAME3" -a "$PARM_OPTION3" == "dr" ]; then echo "backend_hostname3 = '$PARM_HOSTNAME3'"    >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a "$PARM_OPTION3" == "dr" ]; then echo "backend_data_directory3 = '$PGDATA'"      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a "$PARM_OPTION3" == "dr" ]; then echo "backend_port3 = 5493"                     >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a "$PARM_OPTION3" == "dr" ]; then echo "backend_weight3 = 0"                      >> "$CFGFILE"; fi
if [ -n "$PARM_HOSTNAME3" -a "$PARM_OPTION3" == "dr" ]; then echo "backend_flag3 = 'ALLOW_TO_FAILOVER'"      >> "$CFGFILE"; fi

echo "load_balance_mode = $PARM_LOADBALANCE" >> "$CFGFILE"

echo "delegate_IP = '$PARM_VIRTUALIP'" >> "$CFGFILE"
echo "wd_hostname = '$MYHOSTNAME'" >> "$CFGFILE" 

if [ "$MYHOSTNAME" == "$PARM_HOSTNAME2" ]; then 
   echo "wd_priority = 3" >> "$CFGFILE"
   echo "heartbeat_destination0 = '$PARM_HOSTNAME0'" >> "$CFGFILE"
   echo "other_pgpool_hostname0 = '$PARM_HOSTNAME0'" >> "$CFGFILE"
   echo "heartbeat_destination1 = '$PARM_HOSTNAME1'" >> "$CFGFILE"
   echo "other_pgpool_hostname1 = '$PARM_HOSTNAME1'" >> "$CFGFILE"
fi
if [ "$MYHOSTNAME" == "$PARM_HOSTNAME1" ]; then 
   echo "wd_priority = 2" >> "$CFGFILE"
   echo "heartbeat_destination0 = '$PARM_HOSTNAME0'" >> "$CFGFILE"
   echo "other_pgpool_hostname0 = '$PARM_HOSTNAME0'" >> "$CFGFILE"
   echo "heartbeat_destination1 = '$PARM_HOSTNAME2'" >> "$CFGFILE"
   echo "other_pgpool_hostname1 = '$PARM_HOSTNAME2'" >> "$CFGFILE"
fi
if [ "$MYHOSTNAME" == "$PARM_HOSTNAME0" ]; then 
   echo "wd_priority = 1" >> "$CFGFILE"
   echo "heartbeat_destination0 = '$PARM_HOSTNAME1'" >> "$CFGFILE"
   echo "other_pgpool_hostname0 = '$PARM_HOSTNAME1'" >> "$CFGFILE"
   echo "heartbeat_destination1 = '$PARM_HOSTNAME2'" >> "$CFGFILE"
   echo "other_pgpool_hostname1 = '$PARM_HOSTNAME2'" >> "$CFGFILE"
fi

# Use default gateway and primary/secondary/tertiary DNS servers
TRUSTED_SERVER_LIST="'"
for TRUSTED_SERVER in `ip route | grep default | awk '{print $3}' && nmcli dev show | grep DNS | awk '{print $2}'`; do
  if [ "$TRUSTED_SERVER_LIST" != "'" ]; then TRUSTED_SERVER_LIST="$TRUSTED_SERVER_LIST,"; fi
  TRUSTED_SERVER_LIST="${TRUSTED_SERVER_LIST}${TRUSTED_SERVER}"
done
TRUSTED_SERVER_LIST="${TRUSTED_SERVER_LIST}'"
echo "trusted_servers = $TRUSTED_SERVER_LIST" >> "$CFGFILE"

echo; echo "Config file $CFGFILE successfully written using input parameter file $PARMFILE"; echo

exit 0

