#!/usr/bin/bash
# D. Sisk 2020/01/16

# Function declarations
function copy_to {
   scp -q /tmp/server.crt "$1":/etc/pgpool-II/
   scp -q /tmp/server.key "$1":/etc/pgpool-II/
   scp -q /tmp/server.crt "$1":/var/lib/pgsql/9.6/data/
   scp -q /tmp/server.key "$1":/var/lib/pgsql/9.6/data/
}

function check_days_left {
   expire_date_pgpool=`ssh "$1" 'openssl x509 -in /etc/pgpool-II/server.crt -noout -dates' | grep 'notAfter' | cut -d'=' -f2`
   expire_date_postgres=`ssh "$1" 'openssl x509 -in /var/lib/pgsql/9.6/data/server.crt -noout -dates' | grep 'notAfter' | cut -d'=' -f2`
   expire_epoch_pgpool=`date -d "$expire_date_pgpool" +"%s"`
   expire_epoch_postgres=`date -d "$expire_date_postgres" +"%s"`
   let "days_left_pgpool = ($expire_epoch_pgpool - $current_date_epoch) / 86400"
   let "days_left_postgres = ($expire_epoch_postgres - $current_date_epoch) / 86400"
   echo "$vhost:$1 - days left: proxy - $days_left_pgpool   db - $days_left_postgres"
}

function confirm_active {
   cert_pool_disk=`ssh -q "$1" "cat /etc/pgpool-II/server.crt | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'"`
   cert_pool_live=`echo 'Q' | openssl s_client -starttls postgres -connect "$1":5432 2> /dev/null | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'`
   cert_pg_disk=`ssh -q "$1" "cat /var/lib/pgsql/9.6/data/server.crt | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'"`
   cert_pg_live=`echo 'Q' | openssl s_client -starttls postgres -connect "$1":5493 2> /dev/null | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'`
   if [ "$cert_pool_disk" == "$cert_pool_live" ]; then
      echo "OK: $vhost:$1 PGPool on-disk and live certs match"
   else
      echo "ISSUE: $vhost:$1 PGPool on-disk and live certs DO NOT match"
   fi
   if [ "$cert_pg_disk" == "$cert_pg_live" ]; then
      echo "OK: $vhost:$1 PostgreSQL on-disk and live certs match"
   else
      echo "ISSUE: $vhost:$1 PostgreSQL on-disk and live certs DO NOT match"
   fi
}

# Main script body
if [ -z "$1" ] || [ "$1" == '--help' ] || [ "$1" == '-h' ] ; then
   echo "pg-cert_create-distribute.sh v1.00: Create and distribute renewed self-signed SSL certificate and key."
   echo ""
   echo "Usage:"
   echo "  pg-cert_create-distribute.sh --create|--check|--confirm virtual-host.fully.qualified db-host1 db-host2 db-host3"
   echo "     --create:  creates a renewed cert and key with the vhost CN, and scp's them to the specified hosts."
   echo "     --check:   retrieves the days left until expiration for each cert on each specified host."
   echo "     --confirm: confirms that the service is running with the same cert that is on disk on each host."
   echo ""
   echo "Example:"
   echo "  pg-cert_create-distribute.sh --create|--check|--confirm rtp-apl-vpgd.cisco.com rtp-apl-psgd1 rtp-apl-psgd2 rtp-apl-psgd3"
   echo ""
   echo "NOTE: DB cluster requires 3 nodes...specify all 3 nodes even if one or more nodes are down."
   echo ""
   exit 0
elif [ "$#" -ne "5" ]; then
   echo "ERROR:  You must specify all listed parameters"
   echo "  pg-cert_create-distribute.sh --create|--check virtual-host.fully.qualified db-host1 db-host2 db-host3"
   exit 1
fi

option="$1"
vhost="$2"
dbhost1="$3"
dbhost2="$4"
dbhost3="$5"

if [ "$option" == "--create" ]; then
   echo "Creating and distributing new DB SSL certificates..."
   openssl req -new -x509 -days 92 -nodes -text -out /tmp/server.crt -keyout /tmp/server.key -subj "/CN=$vhost"
   chmod 600 /tmp/server.key
   copy_to "$dbhost1"
   copy_to "$dbhost2"
   copy_to "$dbhost3"
   echo "Complete activation using proxy and DB rolling restarts...new certs are not in use until restarts have been completed."   
   exit
fi

if [ "$option" == "--check" ]; then
   echo "Checking expiration date on all DB SSL certificates..."
   current_date_epoch=`date +"%s"`
   check_days_left "$dbhost1"   
   check_days_left "$dbhost2"   
   check_days_left "$dbhost3"   
   echo
   exit
fi

if [ "$option" == "--confirm" ]; then
   echo "Confirming that PostgreSQL and PGPool instances have been started with, and return current, on-disk certificates..."
   confirm_active "$dbhost1"
   confirm_active "$dbhost2"
   confirm_active "$dbhost3"
   echo
   exit
fi
exit


