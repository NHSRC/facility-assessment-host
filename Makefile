jar_file=facilities-assessment-server-0.0.1-SNAPSHOT.jar
metabase_db_file=metabase.db.mv.db

jss_database := facilities_assessment_cg
nhsrc_database := facilities_assessment_nhsrc
nhsrc_port := 80
Today_Day_Name := $(shell date +%a)
jss_database_backup_file := $(jss_database)_$(Day).sql
postgres_user := $(shell id -un)
nhsrc_prod_server=103.35.123.67
nhsrc_slave_server=103.35.123.68

define _start_server
	cd app-servers && nohup java -jar $(jar_file) --database=$1 --server.http.port=$2 --server.port=$3 > log/facilities_assessment.log 2>&1 &
endef

define _stop_server
	-pkill -f 'database=$1'
endef

define _restore_db
	make recreate_db database=$1
	sudo -u $(postgres_user) psql $1 < db/backup/$2
endef

define _flyway_migrate
	flyway -user=nhsrc -password=password -url=jdbc:postgresql://localhost:5432/$1 -schemas=public -locations=filesystem:../facilities-assessment-server/src/main/resources/db/migration/ migrate
endef

define _backup_db
	sudo -u $(postgres_user) pg_dump $1 > db/backup/$1_$2_production.sql
endef

test:
	@echo $(Today_Day_Name)

# <db>
recreate_db:
	sudo -u $(postgres_user) psql postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$(database)' AND pid <> pg_backend_pid()"
	-sudo -u $(postgres_user) psql postgres -c 'drop database $(database)'
	sudo -u $(postgres_user) psql postgres -c 'create database $(database) with owner nhsrc'
	sudo -u $(postgres_user) psql $(database) -c 'create extension if not exists "uuid-ossp"'

restore_jss_db:
	$(call _restore_db,$(jss_database),$(file))

restore_nhsrc_db:
	$(call _restore_db,$(nhsrc_database),$(file))

recreate_schema:
	-psql -Unhsrc postgres -c 'drop database $(db)';
	-psql -Unhsrc postgres -c 'create database $(db) with owner nhsrc';
	-psql $(db) -c 'create extension if not exists "uuid-ossp"';
	flyway -user=nhsrc -password=password -url=jdbc:postgresql://localhost:5432/$(db) -schemas=public clean
	$(call _flyway_migrate,$(db))

backup_nhsrc_db:
	$(call _backup_db,$(nhsrc_database),$(NUM))

pull_jss_db:
	scp nhsrc@192.168.0.155:/home/nhsrc/facilities-assessment-host/db/backup/$(jss_database_backup_file) db/backup/jssprod/

schedule_backup:
	sudo sh schedule-backup.sh

export_nhsrc_db_data_only:
	psql -v ON_ERROR_STOP=1 --echo-all -Unhsrc $(nhsrc_database) < db/deleteMostAssessments.sql
	sudo -u $(postgres_user) pg_dump $(nhsrc_database) -a --inserts -T schema_version -T users -T user_role > db/backup/data_only.sql
# </db>

# <server>
start_server_jss:
	$(call _start_server,$(jss_database),6001,6002)

start_server_nhsrc:
	$(call _start_server,$(nhsrc_database),80,443)

stop_server_jss:
	$(call _stop_server,$(jss_database))

stop_server_nhsrc:
	$(call _stop_server,$(nhsrc_database))
# </server>

# <metabase>
stop_metabase:
	-pkill -f 'java -Dlog4j.configuration=file:log4j.properties -jar metabase.jar'

start_metabase:
	cd metabase && nohup java -Dlog4j.configuration=file:log4j.properties -jar metabase.jar >> log/metabase.log 2>&1 &
# </metabase>

# <metabase_db>
pull_jss_metabase_db:
	scp nhsrc@192.168.0.155:/home/nhsrc/facilities-assessment-host/metabase/$(metabase_db_file) metabase/backup/jssprod/
# </metabase_db>

start_all_nhsrc: start_server_nhsrc start_metabase
stop_all_nhsrc: stop_server_nhsrc stop_metabase
	ps -ef | grep java

download_file:
	rm downloads/$(outputfile)
	cd downloads && wget -c --retry-connrefused --tries=0 -O $(outputfile) $(url)

jss_take_all_db_backup:
	sh db/take-db-backup.sh
	sh metabase/take-db-backup.sh
	ls -lt db/backup/
	ls -lt metabase/backup/

# PUSH TO JSS PRODUCTION
jss_push_server_jar:
	scp ../facilities-assessment-server/build/libs/$(jar_file) nhsrc@192.168.0.155:/home/nhsrc/facilities-assessment-host/app-servers/cg


# <nhsrc>
nhsrc_pull_db:
	scp -P $(nhsrc_server_port) nhsrc@$(nhsrc_prod_server):/home/nhsrc/facilities-assessment-host/db/backup/$(nhsrc_db)_$(DAY).sql db/backup/$(nhsrc_db)_$(DAY)_Prod.sql

nhsrc_push_db:
	scp -P $(nhsrc_server_port) db/backup/$(database_file) nhsrc@$(nhsrc_prod_server):/home/nhsrc/facilities-assessment-host/db/backup/
# </nhsrc>


# <local_development>

_get_server_jar:
	cd ../facilities-assessment-server && make binary
	cp ../facilities-assessment-server/build/libs/$(jar_file) app-servers/$(env)

_make_binary:
	cd ../facilities-assessment-server && make binary

create_release: _make_binary
	cp ../facilities-assessment-server/build/libs/$(jar_file) releases/$(client)/$(release)
# </local_development>

deploy_server_from_download:
	cp downloads/$(jar_file) app-servers/

deploy_app_from_download:
	cp downloads/app.apk app-servers/external/app.apk

deploy_all_from_download: deploy_server_from_download deploy_app_from_download

# prod
nhsrc_cron_backup:
	$(call _backup_db,$(nhsrc_database),$(Today_Day_Name))
	scp /home/nhsrc1/facilities-assessment-host/db/backup/facilities_assessment_nhsrc_$(Today_Day_Name)_production.sql nhsrc2@10.31.37.24:/home/nhsrc2/backup/
	scp /home/nhsrc1/facilities-assessment-host/metabase/metabase.db.mv.db nhsrc2@10.31.37.24:/home/nhsrc2/backup/metabase.db.mv.db_$(Today_Day_Name)

nhsrc_migrate_release_7_7:
	sudo -u $(postgres_user) psql -v ON_ERROR_STOP=1 --echo-all -U$(postgres_user) $(nhsrc_database) < releases/nhsrc/0.7.7/updateSortOrders.sql

nhsrc_migrate_release_7_7_local: nhsrc_migrate_release_7_7

rescore_everything_nhsrc:
	sudo -u $(postgres_user) psql -v ON_ERROR_STOP=1 --echo-all -U$(postgres_user) $(nhsrc_database) < db/rescore-everything.sql