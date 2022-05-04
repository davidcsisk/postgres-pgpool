#!/usr/bin/bash

DFHOST='localhost'
DFPORT='5432'
PWFILE='/var/lib/pgsql/.pgpass'
PWPOOL='/etc/pgpool-II/pool_passwd'
VHOST=`cat /var/lib/pgsql/.virtual_hostname`

if [ `ssh -qt $VHOST 'hostname'` != `ssh -qt $HOSTNAME 'hostname'` ]; then echo "ERROR: manage_db.sh must be run from current virtual host: $VHOST" && exit 1; fi

if [ -z $1 ] || [ $1 == '--help' ] || [ $1 == '-h' ] ; then
   echo "Version 1.2.1"
   echo "Usage: Run this script ONLY on the DB Virtual host/PGPool master"
   echo ""
   echo "./manage_db.sh --list (Lists current databases and owning users)"
   echo "./manage_db.sh --createdb dbname 'password' (Create database and owning user)"
   echo "./manage_db.sh --changepw dbname_or_username 'password' (Change user password)"
   echo "./manage_db.sh --listusers (Lists roles, including owner roles and read-only users)"
   echo "./manage_db.sh --addrouser dbname 'password' (Add read-only user)"
   echo "./manage_db.sh --droprouser dbname username (Drop read-only user)"
   echo "./manage_db.sh --dumpdb dbname (logical backup to /data/.../dumps/)"
   echo "./manage_db.sh --dropDBandUSER dbname (drop database and owning role)"
   echo "./manage_db.sh --REcreateDB dbname (drop database and re-create empty, retain owning role)"
   echo ""
   echo 'Note: To turn off interactive confirmations to use this script with Ansible, call this script like so:'
   echo ' MANAGEDB_AUTOCONFIRM="Y" /var/lib/pgsql/manage_db.sh --action...'
   echo ""
   exit 0;
fi

# Get cluster hostnames to scp the pool_passwd and .pgpass files when they change
NODE0_HOST=`pcp_node_info -w 0 | awk '{print $1}'` 
NODE1_HOST=`pcp_node_info -w 1 | awk '{print $1}'`
NODE2_HOST=`pcp_node_info -w 2 | awk '{print $1}'`

ACTION=$1
DBNAME=$2
PASSWD=$3
DBHOST=$4
DBPORT=$5

if [ -z $DBHOST ]; then DBHOST=$DFHOST; fi
if [ -z $DBPORT ]; then DBPORT=$DFPORT; fi


if [ $ACTION == '--list' ] ; then
   psql -h $DBHOST -p $DBPORT --list
   exit 0;
fi

if [ $ACTION == '--createdb' ] ; then
   if [ $DBNAME == $PASSWD ]; then
      echo
      echo "Password must not match db and owning user name...retry with a different password."
      echo
      exit 1;
   fi
   psql -h $DBHOST -p $DBPORT -U postgres postgres -c "CREATE ROLE $DBNAME WITH LOGIN PASSWORD '$PASSWD';"
   pg_md5 --md5auth --username=$DBNAME $PASSWD
   grep -q "^\*:\*:\*:$DBNAME:" $PWFILE && sed -i "s/^\*:\*:\*:$DBNAME:.*/*:*:*:$DBNAME:$PASSWD/" $PWFILE || echo "*:*:*:$DBNAME:$PASSWD" >> $PWFILE
   # Distribute the password files across all nodes
   scp -q $PWFILE $NODE0_HOST:$PWFILE && scp -q $PWFILE $NODE1_HOST:$PWFILE && scp -q $PWFILE $NODE2_HOST:$PWFILE
   scp -q $PWPOOL $NODE0_HOST:$PWPOOL && scp -q $PWPOOL $NODE1_HOST:$PWPOOL && scp -q $PWPOOL $NODE2_HOST:$PWPOOL
   psql -h $DBHOST -p $DBPORT -U postgres postgres -c "CREATE DATABASE $DBNAME OWNER $DBNAME ENCODING 'UNICODE' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;"
   echo "Database $DBNAME and owning user $DBNAME created...password set in Postgres instances and PGPool."
   exit 0;
fi

if [ $ACTION == '--changepw' ] ; then
   if [ $DBNAME == $PASSWD ]; then
      echo
      echo "Password must not match db and owning user name...retry with a different password."
      echo
      exit 1;
   fi
   psql -h $DBHOST -p $DBPORT -U postgres postgres -c "ALTER ROLE $DBNAME WITH PASSWORD '$PASSWD';"
   pg_md5 --md5auth --username=$DBNAME $PASSWD
   grep -q "^\*:\*:\*:$DBNAME:" $PWFILE && sed -i "s/^\*:\*:\*:$DBNAME:.*/*:*:*:$DBNAME:$PASSWD/" $PWFILE || echo "*:*:*:$DBNAME:$PASSWD" >> $PWFILE
   pgpool reload
   # Distribute the password files across all nodes
   scp -q $PWFILE $NODE0_HOST:$PWFILE && scp -q $PWFILE $NODE1_HOST:$PWFILE && scp -q $PWFILE $NODE2_HOST:$PWFILE
   scp -q $PWPOOL $NODE0_HOST:$PWPOOL && scp -q $PWPOOL $NODE1_HOST:$PWPOOL && scp -q $PWPOOL $NODE2_HOST:$PWPOOL
   echo "Password changed on Postgres instances and PGPool."
   exit 0;
fi

if [ $ACTION == '--listusers' ] ; then
   psql -h $DBHOST -p $DBPORT -c '\du'
   exit 0;
fi

if [ $ACTION == '--addrouser' ] ; then
   psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "CREATE ROLE ${DBNAME}_ro WITH LOGIN PASSWORD '${PASSWD}';"
   pg_md5 --md5auth --username=${DBNAME}_ro $PASSWD
   grep -q "^\*:\*:\*:${DBNAME}_ro:" $PWFILE && sed -i "s/^\*:\*:\*:${DBNAME}_ro:.*/*:*:*:${DBNAME}_ro:$PASSWD/" $PWFILE || echo "*:*:*:${DBNAME}_ro:$PASSWD" >> $PWFILE
   # Distribute the password files across all nodes
   scp -q $PWFILE $NODE0_HOST:$PWFILE && scp -q $PWFILE $NODE1_HOST:$PWFILE && scp -q $PWFILE $NODE2_HOST:$PWFILE
   scp -q $PWPOOL $NODE0_HOST:$PWPOOL && scp -q $PWPOOL $NODE1_HOST:$PWPOOL && scp -q $PWPOOL $NODE2_HOST:$PWPOOL
   psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "GRANT USAGE ON SCHEMA public TO ${DBNAME}_ro;"
   psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DBNAME}_ro;"
   echo "Read-only database user ${DBNAME}_ro created with SELECT privileges on database ${DBNAME}."
   exit 0;
fi

if [ $ACTION == '--droprouser' ] ; then
   psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "DROP OWNED BY $PASSWD RESTRICT;"
   psql -h $DBHOST -p $DBPORT -U postgres $DBNAME -c "DROP ROLE $PASSWD;"
   sed -i "/^$PASSWD:.*/d" /etc/pgpool-II/pool_passwd
   sed -i "/^\*:\*:\*:$PASSWD:.*/d" $PWFILE
   # Distribute the password files across all nodes
   scp -q $PWFILE $NODE0_HOST:$PWFILE && scp -q $PWFILE $NODE1_HOST:$PWFILE && scp -q $PWFILE $NODE2_HOST:$PWFILE
   scp -q $PWPOOL $NODE0_HOST:$PWPOOL && scp -q $PWPOOL $NODE1_HOST:$PWPOOL && scp -q $PWPOOL $NODE2_HOST:$PWPOOL
   echo "Read-only database user $PASSWD dropped."
   exit 0;
fi

if [ $ACTION == '--dumpdb' ] ; then
   DUMPFILE="/data/pg96/dumps/UserDump_${DBNAME}_`date +%a_%Y%m%d_%H%M%S`.sql.gz"
   pg_dump --no-owner -h $DBHOST -p $DBPORT -U postgres $DBNAME | gzip > $DUMPFILE
   echo "Database dump completed...file: $DUMPFILE"
   exit 0;
fi

if [ $ACTION == '--dropDBandUSER' ] ; then
   if [ "$MANAGEDB_AUTOCONFIRM" == "Y"  ]; then 
      RESPONSE="DOIT"
   elif [ -z "$MANAGEDB_AUTOCONFIRM"  ]; then
      echo "Confirm details...this cannot be undone. Use --dumpdb option to take a logical backup first if this is production data."
      echo
      echo "HOST: `hostname`"
      echo "DATABASE: $DBNAME"
      echo
      read -p "Type 'DOIT' to continue with drop operation, or press ENTER to abort: " RESPONSE
   else 
      echo "Either MANAGEDB_AUTOCONFIRM environment variable must be set to "Y", or interactive response is required."
      exit 1;
   fi 
   if [ -z $RESPONSE ]; then
      echo "Drop operation aborted."
   elif [ $RESPONSE == 'DOIT' ]; then
      psql -h $DBHOST -p $DBPORT -U postgres postgres -c "DROP DATABASE $DBNAME;"
      psql -h $DBHOST -p $DBPORT -U postgres postgres -c "DROP ROLE $DBNAME;"
      sed -i "/^$DBNAME:.*/d" /etc/pgpool-II/pool_passwd
      sed -i "/^\*:\*:\*:$DBNAME:.*/d" $PWFILE
   # Distribute the password files across all nodes
   scp -q $PWFILE $NODE0_HOST:$PWFILE && scp -q $PWFILE $NODE1_HOST:$PWFILE && scp -q $PWFILE $NODE2_HOST:$PWFILE
   scp -q $PWPOOL $NODE0_HOST:$PWPOOL && scp -q $PWPOOL $NODE1_HOST:$PWPOOL && scp -q $PWPOOL $NODE2_HOST:$PWPOOL
      echo "Database and owning role $DBNAME dropped."
   else
      echo "Drop operation aborted."
   fi
   exit 0;
fi

if [ $ACTION == '--REcreateDB' ] ; then
   if [ "$MANAGEDB_AUTOCONFIRM" == "Y"  ]; then 
      RESPONSE="DOIT"
   elif [ -z "$MANAGEDB_AUTOCONFIRM"  ]; then
      echo "Confirm details...this cannot be undone. Use --dumpdb option to take a logical backup first if this is production data."
      echo
      echo "HOST: `hostname`"
      echo "DATABASE: $DBNAME"
      echo
      read -p "Type 'DOIT' to continue with drop/re-create operation, or press ENTER to abort: " RESPONSE
   else 
      echo "Either MANAGEDB_AUTOCONFIRM environment variable must be set to "Y", or interactive response is required."
      exit 1;
   fi 
   if [ -z $RESPONSE ]; then
      echo "Drop/re-create operation aborted."
   elif [ $RESPONSE == 'DOIT' ]; then
      psql -h $DBHOST -p $DBPORT -U postgres postgres -c "DROP DATABASE $DBNAME;"
      psql -h $DBHOST -p $DBPORT -U postgres postgres -c "CREATE DATABASE $DBNAME OWNER $DBNAME ENCODING 'UNICODE' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;"
      echo "Database $DBNAME dropped and re-created."
   else
      echo "Drop/re-create operation aborted."
   fi
   exit 0;
fi

