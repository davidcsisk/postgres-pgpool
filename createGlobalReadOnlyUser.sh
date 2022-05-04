#!/usr/bin/bash

if [ -z $1 ] || [ $1 == '--help' ] || [ $1 == '-h' ] ; then
   echo "Usage: create instance-wide read-only user and refresh privileges"
   echo ""
   echo "./create_db.sh db_host ro_username ['ro_password']"
   echo ""
   echo "If password is supplied, the user will be created and all privileges set."
   echo "If password is NOT supplied, assume user already exists and just refresh privileges."
   echo
   exit 0;
fi

DBHOST=$1
ROUSER=$2
ROPASS=$3

DBPORT=5432
PWFILE='/var/lib/pgsql/.pgpass'
PWPOOL='/etc/pgpool-II/pool_passwd'
VHOST=`cat /var/lib/pgsql/.virtual_hostname`

# Only allow script to be run from current pgpool master...password files should only be distributed to the local cluster
if [ `ssh -qt $VHOST 'hostname'` != `ssh -qt $HOSTNAME 'hostname'` ]; then 
  echo "ERROR: this script can only be run from current virtual host: $VHOST" && echo && exit 1
fi

# Only allow script to be run on the cluster this host belongs to...password files should only be distributed to the local cluster
if [ `ssh -qt $VHOST 'hostname'` != `ssh -qt $DBHOST 'hostname'` ]; then 
  echo "ERROR: this script must be run on the virtual host for the target db cluster: $DBHOST" && echo && exit 1
fi

# Get cluster hostnames to scp the pool_passwd and .pgpass files when they change
NODE0_HOST=`pcp_node_info -w 0 | awk '{print $1}'`
NODE1_HOST=`pcp_node_info -w 1 | awk '{print $1}'`
NODE2_HOST=`pcp_node_info -w 2 | awk '{print $1}'`

if [ ! -z "$ROPASS" ]; then
  echo "Creating database user $ROUSER..."
  echo 
  psql -h $DBHOST -p $DBPORT -U postgres postgres -c "create role $ROUSER with login password '$ROPASS';"
  pg_md5 --md5auth --username=${ROUSER} $ROPASS
  grep -q "^\*:\*:\*:${ROUSER}:" $PWFILE && sed -i "s/^\*:\*:\*:${ROUSER}:.*/*:*:*:${ROUSER}:$ROPASS/" $PWFILE || echo "*:*:*:${ROUSER}:$ROPASS" >> $PWFILE
  scp -q $PWFILE $NODE0_HOST:$PWFILE && scp -q $PWFILE $NODE1_HOST:$PWFILE && scp -q $PWFILE $NODE2_HOST:$PWFILE
  scp -q $PWPOOL $NODE0_HOST:$PWPOOL && scp -q $PWPOOL $NODE1_HOST:$PWPOOL && scp -q $PWPOOL $NODE2_HOST:$PWPOOL
fi

for DBNAME in `psql -h $DBHOST -p $DBPORT -t -c "select datname from pg_database where datname not in ('template1','template0','postgres');"`
do
  echo "Granting SELECT privs on database $DBNAME to read-only user $ROUSER."
  psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "GRANT USAGE ON SCHEMA public TO ${ROUSER};"
  psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${ROUSER};"
done
echo

