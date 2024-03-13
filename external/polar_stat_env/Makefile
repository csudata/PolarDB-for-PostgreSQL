# extern/polar_stat_env/Makefile
 
MODULE_big = polar_stat_env
OBJS = polar_stat_env.o
 
EXTENSION = polar_stat_env
DATA = polar_stat_env--1.0.sql
# REGRESS = polar_stat_env
# NO_INSTALLCHECK = 1
POLAR_NO_EXTENSION_USER=1
 
ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = external/polar_stat_env
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
