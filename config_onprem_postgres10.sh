#!/usr/bin/bash
# Run as postgres o/s user

CONFIGFILE=/var/lib/pgsql/10/data/postgresql.conf
SHARED_BUFFERS=$(expr `cat /proc/meminfo | grep MemTotal | awk '{print $2}'` / 2048)

sed -i "s/.*shared_buffers =.*/shared_buffers = ${SHARED_BUFFERS}MB             # NON-DEFAULT: min 128kB/" $CONFIGFILE
sed -i 's/.*max_wal_size =.*/max_wal_size = 10GB				# NON-DEFAULT: in logfile segments, min 1, 16MB each/' $CONFIGFILE
sed -i 's/.*max_connections =.*/max_connections = 1500				# NON-DEFAULT: (change requires restart)/' $CONFIGFILE
sed -i "s/.*listen_addresses =.*/listen_addresses = '*'  			# NON-DEFAULT: what IP address(es) to listen on/" $CONFIGFILE
sed -i "s/.*port =.*/port = 5493  						# NON-DEFAULT: (change requires restart) /" $CONFIGFILE

sed -i 's/.*archive_mode =.*/archive_mode = on					# NON-DEFAULT: allows archiving to be done/' $CONFIGFILE
sed -i 's/.*archive_timeout =.*/archive_timeout = 60				# NON-DEFAULT: force a logfile segment switch after this/' $CONFIGFILE
sed -i "s/.*archive_command =.*/archive_command = 'gzip \< %p \> \/data\/pg10\/wal\/%f.gz'	# NON-DEFAULT: command to archive WAL segments/" $CONFIGFILE

sed -i 's/.*log_lock_waits =.*/log_lock_waits = on				# NON-DEFAULT: log lock waits >= deadlock_timeout/' $CONFIGFILE
sed -i "s/.*log_line_prefix =.*/log_line_prefix = '\< %m:%d:%u:%p \>'		# NON-DEFAULT: special values:/" $CONFIGFILE
sed -i 's/.*log_min_duration_statement =.*/log_min_duration_statement = 1000 	# NON-DEFAULT: -1 is disabled, 0 logs all statements/' $CONFIGFILE 
sed -i 's/.*log_autovacuum_min_duration =.*/log_autovacuum_min_duration = 0 	# NON-DEFAULT: -1 is disabled, 0 logs all autovacuums/' $CONFIGFILE 
sed -i "s/.*log_statement =.*/log_statement = 'ddl' 	                        # NON-DEFAULT: -1 is disabled, 0 logs all autovacuums/" $CONFIGFILE 
sed -i "s/.*log_hostname =.*/log_hostname = on  	                        # NON-DEFAULT: -1 is disabled, 0 logs all autovacuums/" $CONFIGFILE 
sed -i 's/.*lo_compat_privileges = off.*/lo_compat_privileges = on      	# NON-DEFAULT: set LO compatibility with prior versions on/' $CONFIGFILE

sed -i 's/.*wal_level =.*/wal_level = hot_standby				# NON-DEFAULT: minimal, archive, or hot_standby/' $CONFIGFILE
sed -i 's/.*wal_log_hints =.*/wal_log_hints = on       	                        # NON-DEFAULT: also do full page writes of non-critical updates/' $CONFIGFILE
sed -i 's/.*wal_keep_segments =.*/wal_keep_segments = 300                       # NON-DEFAULT: Number of 16Mb WAL segments to keep online/' $CONFIGFILE
sed -i 's/.*hot_standby =.*/hot_standby = on					# NON-DEFAULT: "on" allows queries during recovery/' $CONFIGFILE
sed -i 's/.*max_wal_senders =.*/max_wal_senders = 10                     	# NON-DEFAULT: max number of walsender processes/' $CONFIGFILE
sed -i 's/.*max_replication_slots =.*/max_replication_slots = 10		# NON-DEFAULT: max_replication_slots/' $CONFIGFILE
sed -i 's/.*max_standby_streaming_delay =.*/max_standby_streaming_delay = 60s	# NON-DEFAULT: max delay before canceling queries/' $CONFIGFILE
sed -i 's/.*max_standby_archive_delay =.*/max_standby_archive_delay = 60s  	# NON-DEFAULT: max delay before canceling queries/' $CONFIGFILE
sed -i 's/.*track_commit_timestamp =.*/track_commit_timestamp = on		# NON-DEFAULT: collect timestamp of transaction commit/' $CONFIGFILE

