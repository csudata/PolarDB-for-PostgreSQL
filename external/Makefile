
subdir = external
top_builddir = ..
include $(top_builddir)/src/Makefile.global

# Common
SUBDIRS = polar_vfs
SUBDIRS += polar_monitor
SUBDIRS += polar_monitor_preload

# NB: those will be ignored in minimal mode.
ifeq ($(enable_polar_minimal),no)
SUBDIRS += pgvector
SUBDIRS += polar_worker
SUBDIRS += polar_tde_utils
SUBDIRS += polar_parameter_check
SUBDIRS += polar_stat_env
SUBDIRS += polar_stat_sql
SUBDIRS += polar_csn
SUBDIRS += polar_px
SUBDIRS += smlar
endif #enable_polar_minimal
# Common end

ifeq ($(with_pfsd),yes)
export with_pfsd=yes
endif

$(recurse)
$(recurse_always)
