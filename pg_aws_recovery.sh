#!/usr/bin/bash

if [ -z "$1" ] || [ "$1" == '--help' ] || [ "$1" == '-h' ] ; then
   echo "$0" v1.2
   echo "Usage: Recover Generation 3 AWS Postgres on DR VPC"
   echo
   echo "./pg_aws_recovery.sh customer_shortname DR_vpc_name bastion_IP_address"
   echo
   echo "Example:"
   echo "  ./pg_aws_recovery.sh abc abc-dr.ore 111.222.333.444"
   echo
   exit 0;
fi

if [ `whoami` != "postgres" ]; then
   echo "ERROR: This script must be run as the postgres o/s user."
   exit 1;
fi

echo; date "+%a_%Y-%m-%d_%H:%M:%S - AWS DB Cluster Recovery script started."; echo
CUST_NAME="$1"
DR_VPC="$2"
BASTION_IP="$3"

echo "NOTE: Ensure that you have entered a DR VPC name and NOT a production VPC name...check the values below:"
echo
echo "Customer shortname (the source for the DR Test): $CUST_NAME"
echo "DR VPC (the target VPC to recover the database on): $DR_VPC  (NOTE: Any existing data here will be destroyed)" 
echo "Bastion IP (bastion of the target VPC): $BASTION_IP" 
echo
read -p "Type 'YES-PLEASE' to continue or press ENTER or CNTRL-C otherwise: " RESPONSE
if [ "$RESPONSE" != 'YES-PLEASE' ]; then
   echo; date "+%a_%Y-%m-%d_%H:%M:%S - AWS DB Cluster Recovery script aborted by user."; echo
   exit 0;
fi

# Add or update the matching .ssh/config entry that looks like this:
#   echo "Host *.${DR_VPC}"
#   echo "     ForwardAgent yes"
#   echo "     User postgres"
#   echo "     ProxyCommand ssh ec2-user@111.222.333.444 nc %h %p -w 10"

grep -q $DR_VPC ~/.ssh/config && sed -i '/'"$DR_VPC"'/!b;n;n;n;c\ ProxyCommand ssh ec2-user@'"$BASTION_IP"' nc %h %p -w 10' ~/.ssh/config || cat >> ~/.ssh/config << EOF

Host *.$DR_VPC
     ForwardAgent yes
     User postgres
     ProxyCommand ssh ec2-user@$BASTION_IP nc %h %p -w 10
EOF


eval $(ssh-agent) && ssh-add ~/.ssh/bastion.pem && ssh-add ~/.ssh/jira-datacenter.pem

ssh -qT pgres1.${DR_VPC} "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
ssh -qT pgres2.${DR_VPC} "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
ssh -qT pgpool.${DR_VPC} "source /var/lib/pgsql/.bash_profile && pgpool -m fast stop"
ssh -qT pgpool.${DR_VPC} "source .bash_profile; pg_ctl stop -m fast"
ssh -qT pgres2.${DR_VPC} "source .bash_profile; pg_ctl stop -m fast"
ssh -qT pgres1.${DR_VPC} "source .bash_profile; pg_ctl stop -m fast"
ssh -qT pgres1.${DR_VPC} "rm -rf /tmp/pgpool_status"
ssh -qT pgres2.${DR_VPC} "rm -rf /tmp/pgpool_status"
ssh -qT pgpool.${DR_VPC} "rm -rf /tmp/pgpool_status"

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Transferring lastest available hot backup to $DR_VPC DR VPC..."
scp /aws1/${CUST_NAME}/backups/`ls -t /aws1/${CUST_NAME}/backups/ | head -n 1`/base.tar.gz pgres1.${DR_VPC}:/data/pg96

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Collecting and transferring lastest available WAL archives to $DR_VPC DR VPC..."
mkdir -p /aws1/${CUST_NAME}/temp/
rm -rf /aws1/${CUST_NAME}/temp/*.gz
find /aws1/${CUST_NAME}/archivedwal/ -maxdepth 1 -type f -name '*.gz' -newer `ls -t /aws1/${CUST_NAME}/archivedwal/*backup*.gz | head -n 1` -exec cp {} /aws1/${CUST_NAME}/temp/ \;
scp /aws1/${CUST_NAME}/temp/*.gz pgres1.${DR_VPC}:/data/pg96/wal/

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Restoring hot backup onto pgres1 in $DR_VPC DR VPC..."
ssh -qt pgres1.${DR_VPC} 'cd /data/pg96/data && tar zxvf /data/pg96/base.tar.gz'
ssh -qt pgres1.${DR_VPC} 'cp /etc/pgpool-II/pg_hba.conf /var/lib/pgsql/9.6/data/pg_hba.conf'

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Starting Point-in-time Recovery on pgres1 in $DR_VPC DR VPC..."
ssh -qt pgres1.${DR_VPC} echo "restore_command = \'gunzip -1 \< /data/pg96/wal/%f.gz \> %p\' > /var/lib/pgsql/9.6/data/recovery.conf"
ssh -qT pgres1.${DR_VPC} "source .bash_profile; pg_ctl -w start > /dev/null 2>&1 < /dev/null &"

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Starting PGPool-HA cluster in $DR_VPC DR VPC..."
ssh -qT pgpool.${DR_VPC} "source /var/lib/pgsql/.bash_profile && pgpool"
ssh -qT pgres2.${DR_VPC} "source /var/lib/pgsql/.bash_profile && pgpool"
ssh -qT pgres1.${DR_VPC} "source /var/lib/pgsql/.bash_profile && pgpool"

kill $SSH_AGENT_PID

echo; date "+%a_%Y-%m-%d_%H:%M:%S - Recovery in-progress...examine DB cluster state on $DR_VPC DR VPC..."
echo =================================================================+========================================
echo "NEXT STEPS:"
echo "ssh to vpghost.$DR_VPC"
echo "sudo su - postgres"
echo "./pgcluster_ctl.sh, hit [ENTER] periodically, and examine the output."
echo 
echo 'Once recovery is complete, cluster node 0 will change from "standby" to "primary".'
echo 'After node 0 shows role "primary" and status "up", the applications can be started and connected.'
echo "Recover the two down DB standby's as part of the final steps in a real DR...not necessary for a DR test."
echo ================================================================+=========================================
echo

echo; date "+%a_%Y-%m-%d_%H:%M:%S - AWS DB Cluster Recovery script finished."; echo

