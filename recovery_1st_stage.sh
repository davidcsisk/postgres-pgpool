#!/bin/bash -x
# Recovery script for streaming replication.
# Called by PGPool based on pgpool.conf setting:
# recovery_1st_stage_command = 'recovery_1st_stage.sh'
exec &>> /var/lib/pgsql/.recovery_1st_stage.log
printf "`date`: Starting recovery 1st stage issued from `hostname`...\n"

pgdata=$1
remote_host=$2
remote_pgdata=$3
port=$4
hostname=$(hostname)

ssh -qT postgres@$remote_host "
source ~/.bash_profile
pg_ctl stop -m fast
rm -rf $remote_pgdata/*
pg_basebackup -h $hostname -p $port -U postgres -D $remote_pgdata -X fetch -c fast -R
sed -i 's/^primary_conninfo =.*target_session_attrs=any/& application_name=$remote_host/' $remote_pgdata/recovery.conf
"
printf "`date`: Finished recovery 1st stage...\n\n"

