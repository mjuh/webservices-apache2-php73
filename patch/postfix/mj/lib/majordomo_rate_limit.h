#include <db.h>

#define MJ_DEFAULT_DBS_HOMEDIR "/var/lib/postfix"
#define MJ_DEFAULT_SENDERS_ATIME_DB_NAME "mj_senders_atime.db"
#define MJ_DEFAULT_SENDERS_RATE_DB_NAME "mj_senders_rate.db"
#define MJ_DEFAULT_SENDERS_MAP_DB_NAME "mj_senders_map.db"
#define MJ_DEFAULT_PERIOD_IN_SECONDS 3600
#define MJ_DEFAULT_ALLOW_MESSAGE_PER_PERIOD 120

#define MJ_FIRST_MESSAGE_PERIOD_UPDATED_RATE_UPDATED -2
#define MJ_PERIOD_EXCEED_RATE_UPDATED_PERIOD_UPDATED -1
#define MJ_PERIOD_NOT_EXCEED_RATE_NOT_EXCEED 0
#define MJ_PERIOD_NOT_EXCEED_RATE_EXCEED 1
#define MJ_BLOCKED_BY_BILLING 2
#define MJ_NOT_BLOCKED_BY_BILLING 3

#define MJ_DECREASE_MESSAGE_LIMIT 0x001
#define MJ_FLUSH_RATE_DBS 0x002

typedef struct mj_dbs {
	DB *senders_atime_db_pointer;
	DB *senders_rate_db_pointer;
	DB *senders_map_db_pointer;
	char *dbs_home_dir;
	char *senders_atime_db_name;
	char *senders_rate_db_name;
	char *senders_map_db_name;
} MJ_DBS;

int mj_databases_setup(MJ_DBS *, const char *, FILE *, u_int32_t);
int mj_databases_close(MJ_DBS *);
void mj_initialize_dbs(MJ_DBS *);
int mj_open_database(DB **, const char *, const char *, FILE *, u_int32_t);
void mj_set_db_filenames(MJ_DBS *);
int mj_check_is_blocked_by_billing(DB *, uid_t);
int mj_check_is_rate_exceed(MJ_DBS *, uid_t);
int mj_decrease_senders_message_limit(DB **);
int mj_flush_rate(DB **, DB **);
