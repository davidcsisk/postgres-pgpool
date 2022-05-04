#!/usr/bin/bash

if [ -z $1 ] || [ $1 == '--help' ] || [ $1 == '-h' ] ; then
   echo "Usage: pg_dump databases except postgres and templates"
   echo ""
   echo "./pgdump_databases.sh db_host db_port dump_path"
   echo ""
   exit 0;
fi

DBHOST=$1
DBPORT=$2
DUMPPATH=$3

echo "Dumping globals"
pg_dumpall --globals-only -h $DBHOST -p $DBPORT | gzip > /$DUMPPATH/dump_globals_`date +%a_%Y%m%d_%H%M%S`.sql.gz

for dbname in `psql -h $DBHOST -p $DBPORT -t -c "select datname from pg_database where datname not in ('template1','template0','postgres');"`
do
  echo "Dumping $dbname"
  pg_dump -h $DBHOST -p $DBPORT --no-owner $dbname | gzip > /$DUMPPATH/dump_${dbname}_`date +%a_%Y%m%d_%H%M%S`.sql.gz
done

