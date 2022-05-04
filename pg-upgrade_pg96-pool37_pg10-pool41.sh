#!/usr/bin/bash

# Steps to go from existing PostgreSQL 9.6 -> 10 & PGPool 3.7 -> 4.1
su - postgres -c 'source /var/lib/pgsql/.bash_profile; pg_ctl stop -m fast'

##### as root
# PostgreSQL 10
yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum -y install postgresql10-server postgresql10-contrib

# Change default path, exit and re-sudo
sed -i 's/pgsql-9.6/pgsql-10/' /var/lib/pgsql/.pgsql_profile

su - postgres -c 'rmdir /var/lib/pgsql/10/data && ln -s /data/pg10/data /var/lib/pgsql/10/data'
su - postgres -c 'ln -s /data/pg10/wal /var/lib/pgsql/10/wal'

mkdir -p /data/pg10
mkdir -p /data/pg10/data
mkdir -p /data/pg10/wal
chown -R postgres:postgres /data/pg10

rm -rf /etc/cron.d/postgres_primary
echo "# Postgres PRIMARY and STANDBY jobs" >> /etc/cron.d/postgres_primary
echo "01 01 * * * root /usr/bin/find /data/pg10/wal/ -maxdepth 1 -type f -name '*.gz' -mtime +2 -exec /bin/rm -f {} \;" >> /etc/cron.d/postgres_primary
service crond reload

### PGPool 4.1 for Postgres 10
yum -y erase pgpool-II-pg96*
yum -y install http://www.pgpool.net/yum/rpms/4.1/redhat/rhel-7-x86_64/pgpool-II-release-4.1-1.noarch.rpm
yum -y install pgpool-II-pg10 pgpool-II-pg10-extensions pgpool-II-pg10-debuginfo pgpool-II-pg10-devel
cp /etc/pgpool-II/pcp.conf.rpmsave /etc/pgpool-II/pcp.conf
cp /etc/pgpool-II/pool_hba.conf.rpmsave /etc/pgpool-II/pool_hba.conf


##### as postgres
su - postgres -c 'source /var/lib/pgsql/.bash_profile; initdb'
su - postgres -c 'source .bash_profile; time pg_upgrade --old-bindir=/usr/pgsql-9.6/bin --new-bindir=/usr/pgsql-10/bin --old-datadir=/var/lib/pgsql/9.6/data --new-datadir=/var/lib/pgsql/10/data'

su - postgres -c 'cp /var/lib/pgsql/9.6/data/pgpool_remote_start /var/lib/pgsql/10/data/'
su - postgres -c 'cp /var/lib/pgsql/9.6/data/recovery_1st_stage.sh /var/lib/pgsql/10/data/'
su - postgres -c 'cp /var/lib/pgsql/9.6/data/pg_hba.conf /var/lib/pgsql/10/data/'
su - postgres -c 'source /var/lib/pgsql/.bash_profile; /var/lib/pgsql/config_onprem_postgres10.sh'
su - postgres -c 'source /var/lib/pgsql/.bash_profile; /var/lib/pgsql/config_onprem_pgpool41-hadr.sh'



