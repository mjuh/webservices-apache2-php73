#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include "majordomo_rate_limit.h"

void mj_initialize_dbs(MJ_DBS *my_dbs)
{
	size_t size;
	size = strlen(MJ_DEFAULT_DBS_HOMEDIR) + 1;
	my_dbs->dbs_home_dir = malloc(size);
	snprintf(my_dbs->dbs_home_dir, size, MJ_DEFAULT_DBS_HOMEDIR);
	my_dbs->dbs_home_dir = MJ_DEFAULT_DBS_HOMEDIR;
	my_dbs->senders_atime_db_pointer = NULL;
	my_dbs->senders_rate_db_pointer = NULL;
	my_dbs->senders_map_db_pointer = NULL;
	my_dbs->senders_atime_db_name = NULL;
	my_dbs->senders_rate_db_name = NULL;
	my_dbs->senders_map_db_name = NULL;
}

void mj_set_db_filenames(MJ_DBS *my_dbs)
{
	size_t size;
	size = strlen(my_dbs->dbs_home_dir) + strlen(MJ_DEFAULT_SENDERS_ATIME_DB_NAME) + 2;
	my_dbs->senders_atime_db_name = malloc(size);
	snprintf(my_dbs->senders_atime_db_name, size, "%s/%s", my_dbs->dbs_home_dir, MJ_DEFAULT_SENDERS_ATIME_DB_NAME);

	size = strlen(my_dbs->dbs_home_dir) + strlen(MJ_DEFAULT_SENDERS_RATE_DB_NAME) + 2;
	my_dbs->senders_rate_db_name = malloc(size);
	snprintf(my_dbs->senders_rate_db_name, size, "%s/%s", my_dbs->dbs_home_dir, MJ_DEFAULT_SENDERS_RATE_DB_NAME);

	size = strlen(my_dbs->dbs_home_dir) + strlen(MJ_DEFAULT_SENDERS_MAP_DB_NAME) + 2;
	my_dbs->senders_map_db_name = malloc(size);
	snprintf(my_dbs->senders_map_db_name, size, "%s/%s", my_dbs->dbs_home_dir, MJ_DEFAULT_SENDERS_MAP_DB_NAME);

}

int mj_open_database(DB **dbpp, const char *file_name, const char *program_name, FILE *error_file_pointer, u_int32_t open_flags)
{
	DB *dbp;
	int ret;

	ret = db_create(&dbp, NULL, 0);
	if (ret != 0) {
		fprintf(error_file_pointer, "%s: %s\n", program_name, db_strerror(ret));
		return(ret);
	}
	*dbpp = dbp;
	dbp->set_errfile(dbp, error_file_pointer);
	dbp->set_errpfx(dbp, program_name);

	ret = dbp->open(dbp, NULL, file_name, NULL, DB_BTREE, open_flags, 0);
	if (ret != 0) {
		dbp->err(dbp, ret, "Database '%s' open failed.", file_name);
		return(ret);
	}
	
	return 0;
}

int mj_databases_setup(MJ_DBS *my_dbs, const char *program_name, FILE *error_file_pointer, u_int32_t open_flags)
{
	int ret;
	ret = mj_open_database(&(my_dbs->senders_atime_db_pointer), my_dbs->senders_atime_db_name, program_name, error_file_pointer, open_flags);
	if (ret != 0)
		return(ret);

	ret = mj_open_database(&(my_dbs->senders_rate_db_pointer), my_dbs->senders_rate_db_name, program_name, error_file_pointer, open_flags);
	if (ret != 0)
		return(ret);

	ret = mj_open_database(&(my_dbs->senders_map_db_pointer), my_dbs->senders_map_db_name, program_name, error_file_pointer, open_flags);
	if (ret != 0)
		return(ret);
	return 0;
}

int mj_databases_close(MJ_DBS *my_dbs)
{
	int ret;
	if (my_dbs->senders_atime_db_pointer != NULL) {
		ret = my_dbs->senders_atime_db_pointer->close(my_dbs->senders_atime_db_pointer, 0);
		if (ret != 0)
			fprintf(stderr, "senders atime db close failed: %s\n", db_strerror(ret));
	}
	if (my_dbs->senders_rate_db_pointer != NULL) {
		ret = my_dbs->senders_rate_db_pointer->close(my_dbs->senders_rate_db_pointer, 0);
		if (ret != 0)
			fprintf(stderr, "senders rate db close failed: %s\n", db_strerror(ret));
	}
	if (my_dbs->senders_map_db_pointer != NULL) {
		ret = my_dbs->senders_map_db_pointer->close(my_dbs->senders_map_db_pointer, 0);
		if (ret != 0)
			fprintf(stderr, "senders map db close failed: %s\n", db_strerror(ret));
	}

	
	return 0;
}

int mj_check_is_rate_exceed(MJ_DBS *my_dbs, uid_t user_uid)
{
	DBT key, data_atime, data_rate;
	unsigned access_me_time;
	struct tm *access_me_gmtime;
	unsigned time_per_messages;
	int messages_left;
	int rate_limit;
	int ret;
	
	rate_limit = MJ_DEFAULT_ALLOW_MESSAGE_PER_PERIOD;
	
	access_me_time = (unsigned) time(NULL);
	
	memset(&key, 0, sizeof(DBT));
	memset(&data_atime, 0, sizeof(DBT));
	memset(&data_rate, 0, sizeof(DBT));

	key.data = &user_uid;
	key.size = sizeof(uid_t);
	ret = my_dbs->senders_atime_db_pointer->get(my_dbs->senders_atime_db_pointer, NULL, &key, &data_atime, 0);
	if (ret == DB_KEYEMPTY || ret == DB_NOTFOUND)
		return MJ_FIRST_MESSAGE_PERIOD_UPDATED_RATE_UPDATED;
	else {
		time_per_messages = (access_me_time - *((unsigned *) data_atime.data));
		if (time_per_messages > MJ_DEFAULT_PERIOD_IN_SECONDS)
			return MJ_PERIOD_EXCEED_RATE_UPDATED_PERIOD_UPDATED;
		else {
			my_dbs->senders_rate_db_pointer->get(my_dbs->senders_rate_db_pointer, NULL, &key, &data_rate, 0);
			messages_left = *((int*) data_rate.data);
			if (messages_left > 0)
				return MJ_PERIOD_NOT_EXCEED_RATE_NOT_EXCEED;
		}
	}

	return MJ_PERIOD_NOT_EXCEED_RATE_EXCEED;
}

int mj_check_is_blocked_by_billing(DB *senders_map, uid_t user_uid)
{
	DBT key, data;
	int ret;
	
	memset(&key, 0, sizeof(DBT));
	memset(&data, 0, sizeof(DBT));

	key.data = &user_uid;
	key.size = sizeof(uid_t);

	ret = senders_map->get(senders_map, NULL, &key, &data, 0);
	if (ret == DB_KEYEMPTY || ret == DB_NOTFOUND) {
		return MJ_NOT_BLOCKED_BY_BILLING;
	} else {
		return MJ_BLOCKED_BY_BILLING;
	}
}

int mj_decrease_senders_message_limit(DB **senders_rate)
{
	DBT key, data;
	DB *senders_rate_db;
	short message_limit;
	uid_t user_uid = getuid();
	int ret;

	senders_rate_db = *senders_rate;

	memset(&key, 0, sizeof(DBT));
	memset(&data, 0, sizeof(DBT));

	key.data = &user_uid;
	key.size = sizeof(uid_t);	

	ret = senders_rate_db->get(senders_rate_db, NULL, &key, &data, 0);
	message_limit = *((short *) data.data);
	--message_limit;
	
	data.data = &message_limit;
	data.size = sizeof(short);

	ret = senders_rate_db->put(senders_rate_db, NULL, &key, &data, 0);

	return ret;
}

int mj_flush_rate(DB **senders_rate, DB **senders_atime)
{
	DBT key, data;
	DB *senders_rate_db;
	DB *senders_atime_db;
	uid_t user_uid = getuid();
	int rate_limit = MJ_DEFAULT_ALLOW_MESSAGE_PER_PERIOD;
	unsigned cur_time = (unsigned) time(NULL);

	senders_rate_db = *senders_rate;
	senders_atime_db = *senders_atime;
	
	memset(&key, 0, sizeof(DBT));
	memset(&data, 0, sizeof(DBT));

	key.data = &user_uid;
	key.size = sizeof(uid_t);

	/* update access time for period */
	data.data = &cur_time;
	data.size = sizeof(unsigned);
	senders_atime_db->put(senders_atime_db, NULL, &key, &data, 0);

	/* update message limit for period */
	data.data = &rate_limit;
	data.size = sizeof(int);
	senders_rate_db->put(senders_rate_db, NULL, &key, &data, 0);

	return 0;
}
