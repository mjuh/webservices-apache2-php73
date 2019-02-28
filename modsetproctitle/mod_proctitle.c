/*
 * Copyright 2016 Cloud Linux Zug GmbH
 *
 * Licensed under CLOUD LINUX LICENSE AGREEMENT
 * http://cloudlinux.com/docs/LICENSE.TXT
 * mod_proctitle module
 *
 * author Alexander Demeshko <ademeshko@cloudlinux.com>
 *
 */

#include "proctitle_config.h"

#define MOD_PROCTITLE_VERSION MOD_PROCTITLE_VERSION_MAJOR "." MOD_PROCTITLE_VERSION_MINOR "-" MOD_PROCTITLE_VERSION_RELEASE

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <unixd.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <link.h>
#include <limits.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <semaphore.h>

#include <apr_general.h>
#include <apr_lib.h>
#include <apr_strings.h>
#include <apr_hash.h>
#include <apr_tables.h>

#include <ap_config.h>
#include <ap_config_auto.h>
#include <ap_mpm.h>
#include <mpm_common.h>
#include <httpd.h>
#include <http_log.h>
#include <http_main.h>
#include <http_core.h>
#include <http_config.h>
#include <http_connection.h>
#include <http_protocol.h>
#include <util_filter.h>

#if !APR_HAS_THREADS
#error mod_proctitle requires APR threads, but they are unavailable.
#endif

#ifndef _PCREPOSIX_H
#include <regex.h>
#endif

#define PREFIX "mod_proctitle:"

#define PROCTITLE_THREAD_TITLE_LEN 256
#define PROCTITLE_THREAD_ID_LEN 16

static const char PROCTITLE_OUT_FILTER[] = "PROCTITLE_OUT_FILTER";

static int registered_filter = 0;
static int use_semaphore = 0;
__thread int filter_executed = 0;

#ifdef APACHE2_4
APLOG_USE_MODULE(proctitle);
#endif // APACHE2_4

// configuration data
typedef struct proctitle_dircfg
{
    apr_array_header_t *watch_handlers;	// A list of handlers
} proctitle_dircfg;

typedef struct proctitle_threadcfg
{
    char *thread_title; // PROCTITLE_THREAD_TITLE_LEN bytes mmaped to file descriptor which opened with shm_open
    char shm_name[NAME_MAX];
    char sem_name[NAME_MAX-4];
    sem_t *sem;
} proctitle_threadcfg;

// Thread local storage - https://gcc.gnu.org/onlinedocs/gcc-4.2.4/gcc/Thread_002dLocal.html
static __thread proctitle_threadcfg __threadcfg;

#define MAX_REGEX_LEN 255

// Function searches handler in handler_list
// returns 1 if found, 0 if not
static int
match_handler (apr_array_header_t * handlers_list, const char *handler)
{
  int num_names;
  char **names_ptr;
  char *regex_begin_ptr;	// Pointer to "%" character in the beginning of regex
  char *regex_end_ptr;		// Pointer to "%" character in the end of regex
  char regex_str[MAX_REGEX_LEN + 1];	// Buffer to copy regex from handler_list
  int regex_len;		// Length of regex
  regex_t compiled_regex;	// Compiled regex buffer

  if (handlers_list && handler)
    {
      names_ptr = (char **) handlers_list->elts;
      num_names = handlers_list->nelts;

      // Scan handlers_list
      for (; num_names; ++names_ptr, --num_names)
	{			// Match all the handlers ?
	  if (!strcmp ("*", *names_ptr))
	    return 1;

	  // Current string in handlers_list is regex ?
	  regex_begin_ptr = strchr (*names_ptr, '%');
	  if (regex_begin_ptr)
	    {
	      // Get pointer to "%" character in the end of regex
	      regex_end_ptr = strchr (*names_ptr + 1, '%');

	      // End of regex is not found ?
	      if (!regex_end_ptr)
		continue;

	      // Calculate regex length
	      regex_len = regex_end_ptr - regex_begin_ptr - 1;

	      // Regex is too short or too long ?
	      if ((regex_len < 1) || (regex_len > MAX_REGEX_LEN))
		continue;

	      // Make copy of regex
	      strncpy (regex_str, regex_begin_ptr + 1, regex_len);
	      regex_str[regex_len] = '\0';

	      // Compile regex. Error ?
	      if (regcomp (&compiled_regex, regex_str,
			   REG_EXTENDED | REG_NOSUB))
		continue;

	      // Match handler against compiled regex. Match is found ?
	      if (!regexec (&compiled_regex, handler, 0, NULL, 0))
		{
		  regfree (&compiled_regex);
		  return 1;
		}
	      else
		{
		  regfree (&compiled_regex);
		  continue;
		}
	    }

	  // Compare strings literally
	  if (!strcmp (handler, *names_ptr))
	    return 1;
	}
    }

  return 0;
}

static void *
proctitle_merge_config (apr_pool_t * p, void *BASE, void *ADD)
{
    proctitle_dircfg *base = BASE;
    proctitle_dircfg *add = ADD;
    proctitle_dircfg *cfg =
        (proctitle_dircfg *) apr_pcalloc (p,
					      sizeof(proctitle_dircfg));
    cfg->watch_handlers =
    (add->watch_handlers) ? add->watch_handlers : base->watch_handlers;
    return cfg;
}

static void *
proctitle_create_dir_config (apr_pool_t * p, char *dirspec)
{
    proctitle_dircfg *cfg =
        (proctitle_dircfg *) apr_pcalloc (p,
					      sizeof(proctitle_dircfg));
    if (!cfg)
    {
        ap_log_error (APLOG_MARK, APLOG_ERR, OK, NULL,
		    PREFIX " not enough memory");
        return NULL;
    }
    cfg->watch_handlers = NULL;
    return (void *) cfg;
}

static void 
get_thread_id(char *buf, size_t buflen) {
    int result;
    if (ap_mpm_query(AP_MPMQ_IS_THREADED, &result) == APR_SUCCESS
        && result != AP_MPMQ_NOT_SUPPORTED)
    {
        apr_os_thread_t tid = apr_os_thread_current();
        apr_snprintf(buf, buflen, "%pT", &tid);
    } else {
        apr_snprintf(buf, buflen, "000000000000000");
    }
}

static void 
proctitle_posix_cleanup(void) {

    DIR *dir = opendir("/dev/shm");
    if(dir == NULL) {
        return;
    }

    while(1) {
        struct dirent *direntry = readdir(dir);
        if(direntry == NULL) {
            break;
        }
        if(!strncmp(direntry->d_name, "apache_title_shm_", 17) ) {
            shm_unlink(direntry->d_name);
        } else if(!strncmp(direntry->d_name, "sem.apache_title_sem_", 21) ) {
            sem_unlink(direntry->d_name+4);
        }
    }

    closedir(dir);
}

static apr_status_t 
proctitle_cleanup(void *data) {
    proctitle_posix_cleanup();
    return APR_SUCCESS;
}

static const char *
set_handlers (cmd_parms * cmd, void *mcfg, const char *arg)
{
    proctitle_dircfg *cfg = (proctitle_dircfg *) mcfg;
    const char *err = ap_check_cmd_context (cmd,
					  NOT_IN_DIR_LOC_FILE | NOT_IN_LIMIT);
    if (err != NULL)
    {
        return err;
    }
    if (!cfg->watch_handlers)
    {
        cfg->watch_handlers = apr_array_make (cmd->pool, 2, sizeof (char *));
    }
    *(const char **) apr_array_push (cfg->watch_handlers) = arg;
    return NULL;
}

static proctitle_threadcfg* get_thread_cfg(server_rec *s)
{
    proctitle_threadcfg *tcfg = &__threadcfg;

    if(tcfg->thread_title) {
        return tcfg;
    }

    pid_t tid;
    tid = syscall(SYS_gettid);

    char thread_id[PROCTITLE_THREAD_ID_LEN];
    get_thread_id(thread_id, PROCTITLE_THREAD_ID_LEN);

    snprintf(tcfg->shm_name, NAME_MAX, "/apache_title_shm_%u_%u_%s", getpid(), tid, thread_id);

    // without O_EXCL
    int shm_fd = shm_open(tcfg->shm_name, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR);
    if(shm_fd < 0) {
        ap_log_error (APLOG_MARK, APLOG_WARNING, errno, s,
                        PREFIX " Could not create shm segment(%s)", tcfg->shm_name);
        return NULL;
    }

    if(ftruncate(shm_fd, PROCTITLE_THREAD_TITLE_LEN) != 0) {
        ap_log_error (APLOG_MARK, APLOG_WARNING, errno, s,
                        PREFIX " Could not increase shm segment(%s) to %d bytes",
                        tcfg->shm_name, PROCTITLE_THREAD_TITLE_LEN);
        close(shm_fd);
        shm_unlink(tcfg->shm_name);
        return NULL;
    }

    char* thread_title = mmap(NULL, PROCTITLE_THREAD_TITLE_LEN,
                          PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    if(!thread_title) {
        ap_log_error (APLOG_MARK, APLOG_WARNING, errno, s,
                        PREFIX " Could not mmap shm segment(%s), len %d",
                        tcfg->shm_name, PROCTITLE_THREAD_TITLE_LEN );
        close(shm_fd);
        shm_unlink(tcfg->shm_name);
        return NULL;
    }

    close(shm_fd);
    tcfg->thread_title = thread_title;

    tcfg->sem = NULL;
    if(use_semaphore) {
        // 4 bytes for prefix sem. according to man sem_overview(7)
        snprintf(tcfg->sem_name, NAME_MAX-4, "/apache_title_sem_%u_%u_%s", getpid(), tid, thread_id);
        sem_t *sem = sem_open(tcfg->sem_name, O_CREAT, S_IRUSR | S_IWUSR, 1);
        if(!sem) {
            // will work without semaphore in the case of error
            ap_log_error (APLOG_MARK, APLOG_WARNING, errno, s,
                            PREFIX " Could not create semaphore(%s)",
                            tcfg->sem_name);
            tcfg->sem_name[0] = '\0';
        } else {
            tcfg->sem = sem;
        }
    }
    return tcfg;
}

static const char *
set_proctitle_use_filter (cmd_parms * cmd, void *mcfg, const char *arg)
{
    const char *err = ap_check_cmd_context (cmd, GLOBAL_ONLY);
    if (err != NULL)
    {
      return err;
    }
    if (!apr_strnatcasecmp (arg, "On"))
  	{
	  registered_filter = 1;
  	}

    return NULL;
}

static const char *
set_proctitle_use_semaphore (cmd_parms * cmd, void *mcfg, const char *arg)
{
    const char *err = ap_check_cmd_context (cmd, GLOBAL_ONLY);
    if (err != NULL)
    {
      return err;
    }
    if (!apr_strnatcasecmp (arg, "On"))
  	{
	  use_semaphore = 1;
  	}

    return NULL;
}


// describe used directives
static command_rec proctitle_directives[] = {
    AP_INIT_ITERATE ("WatchHandlers", set_handlers, NULL, RSRC_CONF,
                        "A list of handlers watched"),
    AP_INIT_TAKE1 ("ProctitleUseFilter", set_proctitle_use_filter, NULL,
                    RSRC_CONF,
                    "Use filter for restoring thread title"),
    AP_INIT_TAKE1 ("ProctitleUseSemaphore", set_proctitle_use_semaphore, NULL,
                    RSRC_CONF,
                    "Use semaphore to synchronize access to thread title"),
    {NULL}
};

static int check_for_event_or_worker(){
	module *worker_event_c = NULL;
	worker_event_c = ap_find_linked_module("worker.c");
	if(worker_event_c){
		return 1;
	} else {
		worker_event_c = ap_find_linked_module("event.c");
		if(worker_event_c){
			return 1;
		}
	}
	return 0;
}

static int
proctitle_post_config (apr_pool_t * pconf, apr_pool_t * plog,
                        apr_pool_t * ptemp, server_rec * s)
{
    if (ap_state_query(AP_SQ_MAIN_STATE) == AP_SQ_MS_CREATE_PRE_CONFIG)
        /* First time config phase -- skip. */
        return OK;

    proctitle_posix_cleanup();

    if(!registered_filter){
        registered_filter = check_for_event_or_worker();
    }

    ap_log_error (APLOG_MARK, APLOG_NOTICE, 0, s,
                    PREFIX " version " MOD_PROCTITLE_VERSION " with %s restoring and %s semaphore sync",
                    registered_filter ? "filter" : "old style",
                    use_semaphore ? "with" : "without");

    apr_pool_cleanup_register(pconf, s, proctitle_cleanup, apr_pool_cleanup_null);
    return OK;
}



static void change_proctitle(proctitle_threadcfg *tcfg, request_rec *r)
{
    if(tcfg == NULL || tcfg->thread_title == NULL)
    {
        return;
    }

    int sem_rc;
    if(tcfg->sem) {
        struct timespec abs_timeout;
        abs_timeout.tv_sec = 0;
        abs_timeout.tv_nsec = 10000; // 100 msec

        sem_rc = sem_timedwait(tcfg->sem, &abs_timeout);
        if(sem_rc < 0) {
            ap_log_rerror (APLOG_MARK, APLOG_WARNING, errno, r,
                            "Could not grab semaphore(%s)", tcfg->sem_name );
        }

    } else {
        sem_rc = -1;
    }

    int secs;
    int tenths;
    struct timeval tv;

    if(gettimeofday(&tv, NULL) != 0) {
        secs = time(NULL);
        tenths = 0;
    } else {
        // round it to nearest tenths
        secs = tv.tv_sec;
        tenths = tv.tv_usec/100000 + (tv.tv_usec%100000) / 50000;
        if(tenths >= 10) {
            ++secs;
            tenths = 0;
        }
    }

    memset(tcfg->thread_title, 0, PROCTITLE_THREAD_TITLE_LEN);
    snprintf(tcfg->thread_title, PROCTITLE_THREAD_TITLE_LEN,
             "%d.%d %s %s", secs, tenths, r->hostname,
             ap_escape_logitem(r->pool, r->the_request));

    // semaphore was successfulle grabbed so unlock it
    if(tcfg->sem && sem_rc == 0) {
        sem_post(tcfg->sem);
    }
}


static void restore_proctitle(server_rec *s)
{
    proctitle_threadcfg *tcfg = get_thread_cfg(s);

    if(tcfg == NULL || tcfg->thread_title == NULL)
    {
        return;
    }

    int sem_rc;
    if(tcfg->sem) {
        struct timespec abs_timeout;
        abs_timeout.tv_sec = 0;
        abs_timeout.tv_nsec = 10000; // 100 msec

        sem_rc = sem_timedwait(tcfg->sem, &abs_timeout);
        if(sem_rc < 0) {
            ap_log_error (APLOG_MARK, APLOG_WARNING, errno, s,
                            "Could not grab semaphore(%s)", tcfg->sem_name );
        }

    } else {
        sem_rc = -1;
    }

    memset(tcfg->thread_title, 0, PROCTITLE_THREAD_TITLE_LEN);
    snprintf(tcfg->thread_title, PROCTITLE_THREAD_TITLE_LEN,
                "%s", s->process->short_name);

    // semaphore was successfully grabbed so unlock it
    if(tcfg->sem && sem_rc == 0) {
        sem_post(tcfg->sem);
    }
}

static void proctitle_child_init(apr_pool_t *configpool, server_rec *s) {
    //ap_log_error (APLOG_MARK, APLOG_DEBUG, 0, s,
    //                        "proctitle_child_init: Before restore_proctitle");
    restore_proctitle(s);
    return;
}



module AP_MODULE_DECLARE_DATA proctitle_module =
{ STANDARD20_MODULE_STUFF,
  proctitle_create_dir_config,  /* create directory config */
  proctitle_merge_config,       /* merging directory config */
  NULL,                         /* create server config */
  NULL,                         /* merging server config */
  proctitle_directives//, /* mapping configuration directives */
//  proctitle_register_hooks      /* registering hooks */
};



/**
 * Where are main functionality in this function.
 * This funcion performs after reading request headers
 * and before other processing.
 *
 *
 */
static int
enter_process_request_handler (request_rec * r)
{
    proctitle_dircfg *dircfg = (proctitle_dircfg *)
                 ap_get_module_config (r->per_dir_config, &proctitle_module);
    if (!dircfg)
    {
        return DECLINED;
    }

    if (dircfg->watch_handlers &&
        !match_handler (dircfg->watch_handlers, r->handler))
    {
      return DECLINED;
    }

    proctitle_threadcfg *tcfg = get_thread_cfg(r->server);
    if(!tcfg) {
        return DECLINED;
    }

    if(registered_filter) {
        ap_add_output_filter(PROCTITLE_OUT_FILTER, NULL, r, r->connection);
    }

    //ap_log_rerror (APLOG_MARK, APLOG_DEBUG, 0, r,
    //                        "enter_process_request_handler(%s): Before change_proctitle(%s%s)", 
    //                        __threadcfg.shm_name, r->hostname, r->uri);
    change_proctitle(tcfg, r);

    return DECLINED;
}

static int
leave_process_request_handler (request_rec * r)
{

    if(registered_filter && filter_executed) {
	filter_executed = 0;
	return DECLINED;
    }

    //ap_log_rerror (APLOG_MARK, APLOG_DEBUG, 0, r,
    //                        "leave_process_request_handler(%s): Before restore_proctitle(%s)", 
    //                        __threadcfg.shm_name, __threadcfg.thread_title);
    restore_proctitle(r->server);

    return DECLINED;
}

static apr_status_t proctitle_out_filter(ap_filter_t *f,
                                      apr_bucket_brigade *in)
{
    apr_status_t st;

    if(!registered_filter) {
        ap_remove_output_filter(f);
        return ap_pass_brigade(f->next, in);
    }

    request_rec *r = f->r;

    filter_executed = 1;

    int found_eos = (!APR_BRIGADE_EMPTY(in) && APR_BUCKET_IS_EOS(APR_BRIGADE_LAST(in)));
    st = ap_pass_brigade(f->next, in);
    if (st == APR_SUCCESS) {
        if (!found_eos) {
          // no EOS - don`t restore proctitle
          return st;
        }
    }

    //ap_log_rerror (APLOG_MARK, APLOG_DEBUG, 0, r,
    //                        "proctitle_out_filter(%s): Before restore_proctitle(%s)", 
    //                        __threadcfg.shm_name, __threadcfg.thread_title);
    restore_proctitle(r->server);

    ap_remove_output_filter(f);

    return st;
}


// function for hook register
static void
proctitle_register_hooks (apr_pool_t * p)
{
    static const char *const aszPre[] = { "mod_include.c", "mod_php.c",
        "mod_cgi.c", NULL
    };

    ap_hook_post_config (proctitle_post_config, NULL, NULL, APR_HOOK_MIDDLE);
    ap_hook_child_init(proctitle_child_init, NULL, NULL, APR_HOOK_MIDDLE);
    ap_hook_handler (enter_process_request_handler, NULL, aszPre, APR_HOOK_REALLY_FIRST);
    ap_hook_log_transaction (leave_process_request_handler, NULL, NULL, APR_HOOK_LAST);

    ap_register_output_filter(PROCTITLE_OUT_FILTER, proctitle_out_filter,
                                NULL, AP_FTYPE_CONTENT_SET);
}


/**
 * Describing structure of Apache module
*/

//module AP_MODULE_DECLARE_DATA proctitle_module =
//{ STANDARD20_MODULE_STUFF,
//  proctitle_create_dir_config,	/* create directory config */
//  proctitle_merge_config,	/* merging directory config */
//  NULL,				/* create server config */
//  NULL,				/* merging server config */
//  proctitle_directives,	/* mapping configuration directives */
//  proctitle_register_hooks	/* registering hooks */
//};
