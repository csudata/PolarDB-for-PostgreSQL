/* -------------------------------------------------------------------------
 *
 * pgstat_backend.c
 *	  Implementation of backend statistics.
 *
 * This file contains the implementation of backend statistics.  It is kept
 * separate from pgstat.c to enforce the line between the statistics access /
 * storage implementation and the details about individual types of
 * statistics.
 *
 * This statistics kind uses a proc number as object ID for the hash table
 * of pgstats.  Entries are created each time a process is spawned, and are
 * dropped when the process exits.  These are not written to the pgstats file
 * on disk.  Pending statistics are managed without direct interactions with
 * PgStat_EntryRef->pending, relying on PendingBackendStats instead so as it
 * is possible to report data within critical sections.
 *
 * Copyright (c) 2001-2025, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *	  src/backend/utils/activity/pgstat_backend.c
 * -------------------------------------------------------------------------
 */

#include "postgres.h"

#include "storage/bufmgr.h"
#include "utils/memutils.h"
#include "utils/pgstat_internal.h"

/*
 * Backend statistics counts waiting to be flushed out. These counters may be
 * reported within critical sections so we use static memory in order to avoid
 * memory allocation.
 */
static PgStat_BackendPending PendingBackendStats;

/*
 * Utility routines to report I/O stats for backends, kept here to avoid
 * exposing PendingBackendStats to the outside world.
 */
void
pgstat_count_backend_io_op_time(IOObject io_object, IOContext io_context,
								IOOp io_op, instr_time io_time)
{
	Assert(track_io_timing);

	if (!pgstat_tracks_backend_bktype(MyBackendType))
		return;

	Assert(pgstat_tracks_io_op(MyBackendType, io_object, io_context, io_op));

	INSTR_TIME_ADD(PendingBackendStats.pending_io.pending_times[io_object][io_context][io_op],
				   io_time);
}

void
pgstat_count_backend_io_op(IOObject io_object, IOContext io_context,
						   IOOp io_op, uint32 cnt, uint64 bytes)
{
	if (!pgstat_tracks_backend_bktype(MyBackendType))
		return;

	Assert(pgstat_tracks_io_op(MyBackendType, io_object, io_context, io_op));

	PendingBackendStats.pending_io.counts[io_object][io_context][io_op] += cnt;
	PendingBackendStats.pending_io.bytes[io_object][io_context][io_op] += bytes;
}

/*
 * Returns statistics of a backend by proc number.
 */
PgStat_Backend *
pgstat_fetch_stat_backend(ProcNumber procNumber)
{
	PgStat_Backend *backend_entry;

	backend_entry = (PgStat_Backend *) pgstat_fetch_entry(PGSTAT_KIND_BACKEND,
														  InvalidOid, procNumber);

	return backend_entry;
}

/*
 * Flush out locally pending backend IO statistics.  Locking is managed
 * by the caller.
 */
static void
pgstat_flush_backend_entry_io(PgStat_EntryRef *entry_ref)
{
	PgStatShared_Backend *shbackendent;
	PgStat_BktypeIO *bktype_shstats;
	PgStat_PendingIO pending_io;

	/*
	 * This function can be called even if nothing at all has happened for IO
	 * statistics.  In this case, avoid unnecessarily modifying the stats
	 * entry.
	 */
	if (pg_memory_is_all_zeros(&PendingBackendStats.pending_io,
							   sizeof(struct PgStat_PendingIO)))
		return;

	shbackendent = (PgStatShared_Backend *) entry_ref->shared_stats;
	bktype_shstats = &shbackendent->stats.io_stats;
	pending_io = PendingBackendStats.pending_io;

	for (int io_object = 0; io_object < IOOBJECT_NUM_TYPES; io_object++)
	{
		for (int io_context = 0; io_context < IOCONTEXT_NUM_TYPES; io_context++)
		{
			for (int io_op = 0; io_op < IOOP_NUM_TYPES; io_op++)
			{
				instr_time	time;

				bktype_shstats->counts[io_object][io_context][io_op] +=
					pending_io.counts[io_object][io_context][io_op];
				bktype_shstats->bytes[io_object][io_context][io_op] +=
					pending_io.bytes[io_object][io_context][io_op];
				time = pending_io.pending_times[io_object][io_context][io_op];

				bktype_shstats->times[io_object][io_context][io_op] +=
					INSTR_TIME_GET_MICROSEC(time);
			}
		}
	}

	/*
	 * Clear out the statistics buffer, so it can be re-used.
	 */
	MemSet(&PendingBackendStats.pending_io, 0, sizeof(PgStat_PendingIO));
}

/*
 * Flush out locally pending backend statistics
 *
 * "flags" parameter controls which statistics to flush.  Returns true
 * if some statistics could not be flushed due to lock contention.
 */
bool
pgstat_flush_backend(bool nowait, bits32 flags)
{
	PgStat_EntryRef *entry_ref;

	if (!pgstat_tracks_backend_bktype(MyBackendType))
		return false;

	if (pg_memory_is_all_zeros(&PendingBackendStats,
							   sizeof(struct PgStat_BackendPending)))
		return false;

	entry_ref = pgstat_get_entry_ref_locked(PGSTAT_KIND_BACKEND, InvalidOid,
											MyProcNumber, nowait);
	if (!entry_ref)
		return true;

	/* Flush requested statistics */
	if (flags & PGSTAT_BACKEND_FLUSH_IO)
		pgstat_flush_backend_entry_io(entry_ref);

	pgstat_unlock_entry(entry_ref);

	return false;
}

/*
 * Check if there are any backend stats waiting for flush.
 */
bool
pgstat_backend_have_pending_cb(void)
{
	return (!pg_memory_is_all_zeros(&PendingBackendStats,
									sizeof(struct PgStat_BackendPending)));
}

/*
 * Callback to flush out locally pending backend statistics.
 *
 * If some stats could not be flushed due to lock contention, return true.
 */
bool
pgstat_backend_flush_cb(bool nowait)
{
	return pgstat_flush_backend(nowait, PGSTAT_BACKEND_FLUSH_ALL);
}

/*
 * Create backend statistics entry for proc number.
 */
void
pgstat_create_backend(ProcNumber procnum)
{
	PgStat_EntryRef *entry_ref;
	PgStatShared_Backend *shstatent;

	entry_ref = pgstat_get_entry_ref_locked(PGSTAT_KIND_BACKEND, InvalidOid,
											MyProcNumber, false);
	shstatent = (PgStatShared_Backend *) entry_ref->shared_stats;

	/*
	 * NB: need to accept that there might be stats from an older backend,
	 * e.g. if we previously used this proc number.
	 */
	memset(&shstatent->stats, 0, sizeof(shstatent->stats));
	pgstat_unlock_entry(entry_ref);

	MemSet(&PendingBackendStats, 0, sizeof(PgStat_BackendPending));
}

/*
 * Backend statistics are not collected for all BackendTypes.
 *
 * The following BackendTypes do not participate in the backend stats
 * subsystem:
 * - The same and for the same reasons as in pgstat_tracks_io_bktype().
 * - B_BG_WRITER, B_CHECKPOINTER, B_STARTUP and B_AUTOVAC_LAUNCHER because their
 * I/O stats are already visible in pg_stat_io and there is only one of those.
 *
 * Function returns true if BackendType participates in the backend stats
 * subsystem and false if it does not.
 *
 * When adding a new BackendType, also consider adding relevant restrictions to
 * pgstat_tracks_io_object() and pgstat_tracks_io_op().
 */
bool
pgstat_tracks_backend_bktype(BackendType bktype)
{
	/*
	 * List every type so that new backend types trigger a warning about
	 * needing to adjust this switch.
	 */
	switch (bktype)
	{
		case B_INVALID:
		case B_AUTOVAC_LAUNCHER:
		case B_DEAD_END_BACKEND:
		case B_ARCHIVER:
		case B_LOGGER:
		case B_WAL_RECEIVER:
		case B_WAL_WRITER:
		case B_WAL_SUMMARIZER:
		case B_BG_WRITER:
		case B_CHECKPOINTER:
		case B_STARTUP:
			return false;

		case B_AUTOVAC_WORKER:
		case B_BACKEND:
		case B_BG_WORKER:
		case B_STANDALONE_BACKEND:
		case B_SLOTSYNC_WORKER:
		case B_WAL_SENDER:
			return true;
	}

	return false;
}

void
pgstat_backend_reset_timestamp_cb(PgStatShared_Common *header, TimestampTz ts)
{
	((PgStatShared_Backend *) header)->stats.stat_reset_timestamp = ts;
}