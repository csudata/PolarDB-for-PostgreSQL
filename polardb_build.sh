#!/bin/bash
# 
# Copyright (c) 2020, Alibaba Group Holding Limited
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

##################### PHASE 1: set up parameter #####################
usage () {
cat <<EOF

  This script is to be used to compile PG core source code (PG engine code without files within contrib and external)
  It can be called with following options:
  --basedir=<temp dir for PG installation>, specifies which dir to install PG to, note this dir would be cleaned up before being used
  --datadir=<temp dir for databases>], specifies which dir to store database cluster, note this dir would be cleaned up before being used
  --conf=<file path for postgresql.conf>, specifies the configure file to use
  --user=<user to start PG>, specifies which user to run PG as
  --port=<port to run PG on>, specifies which port to run PG on
  --debug=[on|off], specifies whether to compile PG with debug mode (affecting gcc flags)
  -c,--coverage, specifies whether to build PG with coverage option
  --nc,--nocompile, prevents re-compilation, re-installation, and re-initialization
  -t,-r,--regress, runs regression test after compilation and installation.
  -m --minimal compile with minimal extention set
  --withrep init the database with a hot standby replica
  --withstandby init the database with a hot standby replica
  --pg_bld_rep_port=<port to run PG rep on>, specifies which port to run PG replica on
  --pg_bld_standby_port=<port to run PG standby on>, specifies which port to run PG standby on
  --repdir=<temp dir for databases>], specifies which dir to store replica data, note this dir would be cleaned up before being used
  --storage=localfs, specify storage type
  -e,--extension, run extension test
  --with-tde, TDE enable
  --with-dma, DMA enable
  --with-pfsd, PFSD enable
  --fault-injector, faultinjector enable
  --without-fbl, run without flashback log
  --extra-conf, add an extra conf file

  Please lookup the following secion to find the default values for above options.

  Typical command patterns to kick off this script:

  1) To just cleanup, re-compile, re-install and get PG restart:
  polardb_build.sh
  2) To run all steps included 1), as well as run the ALL regression test cases:
  polardb_build.sh -t
  3) To cleanup and re-compile with code coverage option:
  polardb_build.sh -c
  4) To run the tests besides 3).
  polardb_build.sh -c -t
  5) To run with specific port, user, and/or configuration file
  polardb_build.sh --port=5501 --user=pg001 --conf=/root/data/postgresql.conf
  6) To run on local pfs
  polardb_build.sh --storage=localfs
  7) To run with a replica (it also works with --storage=localfs)
  polardb_build.sh --withrep
  8) To run with a standby (it also works with --storage=localfs)
  polardb_build.sh --withstandby
  9) To run all the tests (make check)(include src/test,src/pl,src/interfaces/ecpg,contrib,external)
  polardb_build.sh -r-check-all
  10) To run all the tests (make installcheck)(include src/test,src/pl,src/interfaces/ecpg,contrib,external)
  polardb_build.sh -r-installcheck-all

EOF

  exit 0;
}

su_eval() {
  if [[ -z $su_str ]];
  then
    eval "$1"
  else
    eval "$su_str \"$1\" "
  fi
}

function del_cov() {
  su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_master_dir restart -w -c -o '-p $pg_bld_port'"
  if [[ $withrep == "yes" ]];
  then
    for i in $(seq 1 $repnum)
    do
      if [[ $repnum == "1" ]];
      then
        pg_bld_replica_dir_n=${pg_bld_replica_dir}
      else
        pg_bld_replica_dir_n=${pg_bld_replica_dir}${i}
      fi
      pg_bld_rep_port_n=$(($pg_bld_rep_port+$i-1))
      su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_replica_dir_n restart -w -c -o '-p $pg_bld_rep_port_n'"
    done
  fi
  if [[ $withstandby == "yes" ]];
  then
    su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_standby_dir restart -w -c -o '-p $pg_bld_standby_port'"
  fi

  make coverage-html -sj`getconf _NPROCESSORS_ONLN`
  perl delta_coverage.pl -p $prev_commit

  cd coverage
  sed -i -E "s/Line Coverage/Line Coverage\/<a href=\"delta_coverage.txt\">Delta Coverage<\/a>/" index.html
  sed -i -E "s/Line Coverage/Line Coverage\/<a href=\"delta_coverage.txt\">Delta Coverage<\/a>/" index-sort-l.html
  cd ..

}

function px_init() {
  echo "################################ px_init ################################"
  echo "polar_enable_px=0" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_check_workers=0" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_replay_wait=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_dop_per_node=3" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_max_workers_number=0" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_cte_shared_scan=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_partition=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_left_index_nestloop_join=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_wait_lock_timeout=1800000" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_partitionwise_join=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_optimizer_multilevel_partitioning=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_max_slices=1000000" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_adps=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_adps_explain_analyze=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_trace_heap_scan_flow=1" >> $pg_bld_master_dir/postgresql.conf
  echo "polar_px_enable_spi_read_all_namespaces=1" >> $pg_bld_master_dir/postgresql.conf
  su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_master_dir reload"
}

function check_core() {
  pg_bld_master_dir_n=${pg_bld_master_dir}
  corefile=`find ${pg_bld_master_dir_n} -name core.*`
  if [[ -n $corefile ]];
  then
    echo "find core in master" >> testlog
    exit
  fi

  if [[ $withrep == "yes" ]];
  then
    for i in $(seq 1 $repnum)
    do
      if [[ $repnum == "1" ]];
      then
        pg_bld_replica_dir_n=${pg_bld_replica_dir}
        corefile=`find ${pg_bld_replica_dir_n} -name core.*`
        if [[ -n $corefile ]];
        then
          echo "find core in replica" >> testlog
          exit
        fi
      else
        pg_bld_replica_dir_n=${pg_bld_replica_dir}${i}
        corefile=`find ${pg_bld_replica_dir_n} -name core.*`
        if [[ -n $corefile ]];
        then
          echo "find core in replica" >> testlog
          exit
        fi
      fi
    done
  fi
}

function check_failed_case() {
  failcases=`grep "\.\. FAILED"  testlog | head -n 1`
  failcases=`grep "\.\. Failed"  testlog | head -n 1`$failcases
  failcases=`grep "CMake Error at" testlog| head -n 1`$failcases
  failcases=`grep "could not connect to server" testlog | head -n 1`$failcases
  failcases=`grep "terminating connection due to administrator command" testlog | head -n 1`$failcases
  failcases=`grep "FAIL" testlog | head -n 1`$failcases
  failcases=`grep "Dubious, test returned 255" testlog | head -n 1`$failcases
  failcases=`grep "FATAL" testlog | head -n 1`$failcases
  failcases=`grep "Error 2" testlog | head -n 1`$failcases

  check_core

  if [[ -n $failcases ]];
  then
    echo ""
    echo ""
    echo "============================"
    echo "Suspected failing records:"
    echo "============================"
    echo ""
    grep "\.\. FAILED"  testlog
    grep "\.\. Failed"  testlog
    grep "CMake Error at" testlog
    grep "could not connect to server" testlog
    grep "terminating connection due to administrator command" testlog
    grep "FATAL" testlog
    grep "Dubious, test returned 255" testlog
  else
    rm -f testlog
    echo ""
    echo ""
    echo "==========================="
    echo "Congratulations!! All cases" $1 "passed!"
    echo "==========================="
    echo ""
  fi
}

pg_bld_prefix=$HOME
pg_bld_basedir=$pg_bld_prefix/tmp_basedir_polardb_pg_1100_bld
pg_bld_data_dir=$pg_bld_prefix/tmp_datadir_polardb_pg_1100_bld
pg_bld_master_dir=$pg_bld_prefix/tmp_master_dir_polardb_pg_1100_bld
pg_bld_replica_dir=$pg_bld_prefix/tmp_replica_dir_polardb_pg_1100_bld
pg_bld_standby_dir=$pg_bld_prefix/tmp_standby_dir_polardb_pg_1100_bld
pg_bld_standby_data_dir=$pg_bld_prefix/tmp_standby_datadir_polardb_pg_1100_bld

pg_bld_user=`whoami`
pg_bld_port=5432
pg_bld_rep_port=5433
pg_bld_standby_port=5435
pg_db_user=postgres
current_branch=`git rev-parse --abbrev-ref HEAD`
if [[ $current_branch == "HEAD" ]];
then
  current_branch=`git rev-parse HEAD~0`
fi
prev_commit=`git rev-parse HEAD~1`
next_commit=`git rev-parse HEAD~0`
nocompile=off
debug_mode=off
coverage=off
regress_test=off
regress_test_ng=off

px_debug_mode=off

regress_test_quick=off

make_installcheck_world=off
make_check_world=off
minimal_compile=off
static_check=off
tap_tests=off
delta_cov=off
enable_asan=off
tde=off
dma=off
fault_injector=off
enable_flashback_log=on
pfsd=off


enc_func="aes-256"

SRCDIR=`pwd`                    # 源码文件目录

# unset PG* envs
unset PGPORT
unset PGDATA
unset PGHOST
unset PGDATABASE
unset PGUSER

function set_env() {
  export PGPORT=$pg_bld_port
  export PGUSER=postgres
  export PGHOST=$pg_bld_master_dir
  export PGDATABASE=postgres
}

# is data dir path specified by user
data_dir_specified=no
rep_dir_specified=no
standby_dir_specified=no
withrep=no
withstandby=no
need_initdb=no
need_initrep=no
noclean=no
normbasedir=no
noinit=no
withpx=no
initpx=no
repnum=1

for arg do
  # the parameter after "=", or the whole $arg if no match
  val=`echo "$arg" | sed -e 's;^--[^=]*=;;'`

  #
  # Note we use eval for dir assignment to expand ~
  #
  case "$arg" in
    --basedir=*)                eval pg_bld_basedir="$val" ;;
    --datadir=*)                eval pg_bld_master_dir="$val"; data_dir_specified=yes ;;
    --repdir=*)                 eval pg_bld_replica_dir="$val"; rep_dir_specified=yes ;;
    --standbydir=*)             eval pg_bld_standby_dir="$val"; standby_dir_specified=yes ;;
    --user=*)                   pg_bld_user="$val" ;;
    --port=*)                   pg_bld_port="$val" ;;
    --repport=*)                pg_bld_rep_port="$val" ;;
    --standbyport=*)            pg_bld_standby_port="$val" ;;
    -h|--help)                  usage ;;
    --nc|--nocompile)           nocompile=on ;;
    --debug=*)                  debug_mode="$val" ;;
    --px-debug=*)               px_debug_mode="$val" ;;
    --prev_commit=*)            prev_commit="$val" ;;
    --next_commit=*)            next_commit="$val" ;;
    --withrep*)                 withrep=yes ;;
    --withstandby*)             withstandby=yes ;;
    --withpx*)                  withpx=yes ;;
    --initpx*)                  withpx=yes;
                                initpx=yes ;;
    --repnum*)                  repnum="$val" ;;
    -c|--coverage)              debug_mode=on;
                                coverage=on
                                ;;
    -r|-t|--regress)            regress_test=on
                                ;;
    -r-ng)                      regress_test_ng=on
                                tap_tests=on
                                ;;
    -r-quick|-t-quick)          regress_test_quick=on
                                ;;
    -r-px)                      regress_test=on;
                                withpx=yes;
                                initpx=yes
                                ;;
    -r-check-all)               make_check_world=on;
                                tap_tests=on
                                ;;
    -r-installcheck-all)        make_installcheck_world=on;
                                tap_tests=on
                                ;;
    --noclean)                  noclean=yes ;; #do not make distclean
    --normbasedir)              normbasedir=yes ;; #do not remove data and base dirs
    -m|--minimal)               minimal_compile=on ;;
    --storage=*)                storage="$val" ;;  #default localfs, don't delete it for habit
    --tap)                      tap_tests=on;;
    --delta_coverage)           delta_coverage=on
                                ;;
    -e|--extension)             extension_test=on
                                ;;
    -r-external)                external_test=on
                                ;;
    -r-contrib)                 contrib_test=on
                                ;;
    -r-pl)                      pl_test=on
                                ;;
    --asan)                     enable_asan=on;;
    --with-tde)                 tde=on
                                ;;
    --enc=*)                    eval enc_func="$val" #default aes-256 ,support aes-256、aes-128、sm4
                                ;;
    --with-dma)                 dma=on
                                ;;
    --with-pfsd)                pfsd=on
                                ;;
    --fault-injector)           fault_injector=on
                                ;;
    --without-fbl)              enable_flashback_log=off
                                ;;
    --noinit)                   noinit=yes
                                ;;
    --extra-conf=*)             extra_conf="$val"
                                ;;
    *)                          echo "wrong options : $arg";
                                exit 1
                                ;;
  esac
done

set_env

if [[ $delta_coverage == "on" ]];
then
  del_cov;
  exit;
fi

su_str=
if [[ "$EUID" == 0 ]];
then
  echo "Running with user $pg_bld_user!"
  su_str="su $pg_bld_user -c "
fi

if [[ $withpx == "yes" ]];
then
  echo "################################ build with px ################################"
  configure_flag+=" --enable-polar-px"

  if [[ $noinit == "no" ]];
  then
    withrep="yes"
    if [[ $repnum == "1" ]];
    then
      repnum=2
    fi
  fi
fi

if [[ $initpx == "yes" ]];
then
  export PG_REGRESS_PX_MODE="--polar-parallel-execution --load-extension=polar_px"
fi


####### PHASE 2: cleanup dir and env, and set new dir and env #######
# stop server maybe failed, just ignore
set +e

# cleanup dirs and PG process
su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_master_dir stop -m i"
su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_replica_dir stop -m i"
su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_standby_dir stop -m i"

# reset
set -e

# must clean before dir remove, some module depend on base_dir/bin/pg_config
if [[ $noclean == "no" ]];
then
  make -s distclean || true
fi

mkdir -p $pg_bld_basedir
if [[ $noinit == "no" ]];
then
mkdir -p $pg_bld_master_dir
mkdir -p $pg_bld_replica_dir
mkdir -p $pg_bld_data_dir
fi

if [[ $normbasedir == "no" ]] && [[ -n $pg_bld_basedir ]] && [[ -d $pg_bld_basedir/bin ]];
then
  rm -fr $pg_bld_basedir/*
fi

# cleanup datadir only if it is not specified explicitly by user (so a default trival one)
if [[ $noinit == "no" ]] && [[ $data_dir_specified == "no" ]] && [[ -n $pg_bld_master_dir ]];
then
  rm -fr $pg_bld_master_dir/*
  rm -fr $pg_bld_data_dir/*
  need_initdb=yes
fi

gcc_opt_level_flag="-g -pipe -Wall -grecord-gcc-switches -I/usr/include/et"
tde_initdb_args=""

if [[ $debug_mode == "on" ]];
then
  gcc_opt_level_flag+=" -ggdb -O0 -g3 -fno-omit-frame-pointer -fstack-protector-strong --param=ssp-buffer-size=4"
  configure_flag+=" --enable-debug --enable-cassert --enable-tap-tests"
  export COPT="-Werror"
else
  gcc_opt_level_flag+=" -O3"
  if [[ $withpx == "yes" ]];
  then
    gcc_opt_level_flag+=" -Wp,-D_FORTIFY_SOURCE=2"
  fi
fi

if [[ $px_debug_mode == "on" ]];
then
  configure_flag+=" --enable-gpos-debug"
fi

if [[ $enable_asan == "on" ]];
then
    gcc_opt_level_flag+=" -fsanitize=address -fno-omit-frame-pointer"
    #Asan core file is huge (>15T), so we do not allow coredump.
    export ASAN_OPTIONS="alloc_dealloc_mismatch=0:"
fi

if [[ $coverage == "on" ]];
then
  configure_flag+=" --enable-coverage"
fi

if [[ $tap_tests == "on" ]];
then
  configure_flag+=" --enable-tap-tests"
fi

if [[ $fault_injector == "on" ]]
then
  configure_flag+=" --enable-inject-faults"
fi

if [[ $minimal_compile == "on" ]];
then
  configure_flag+=" --without-readline --without-zlib --enable-polar-minimal"
else
  configure_flag+=" --with-openssl --with-libxml --with-perl --with-python --with-tcl --with-pam --with-gssapi --enable-nls --with-libxslt --with-ldap --with-uuid=e2fs --with-icu --with-llvm"
fi

if [[ $pfsd == "on" ]];
then
  configure_flag+=" --with-pfsd"
fi

dma_regress_opt=
if [[ $dma == "on" ]];
then
  dma_regress_opt="DMA_OPTS=cluster"
  configure_flag+=" --with-dma"
fi

# setup env
export CFLAGS="  $gcc_opt_level_flag"
export CXXFLAGS="$gcc_opt_level_flag"
export LDFLAGS="-Wl,-rpath,'\$\$ORIGIN/../lib'"

# to get rid of postgis db creation error
export LANG=en_US.UTF-8

# need to set LD_LIBRARY_PATH for ecpg test cases to link correct libraries when compiled and run by its pg_regress
export LD_LIBRARY_PATH=$pg_bld_basedir/lib:$LD_LIBRARY_PATH

# may be needed by some module Makefile to get the correct pg_config
export PATH=$pg_bld_basedir/bin:$PATH

#################### PHASE 3: compile and install ###################
if [[ $nocompile == "off" ]];
then
  ./configure --prefix=$pg_bld_basedir --with-pgport=$pg_bld_port $common_configure_flag $configure_flag

  for target in . contrib external
  do
    make -sj`getconf _NPROCESSORS_ONLN` -C $target
    make install -s -C $target
  done
fi ##nocoimpile == off

###################### PHASE 4 Test: run test cases in non-polar  ######################
if [[ $make_check_world == "on" ]];
then
  unset COPT

  su_eval "make $dma_regress_opt check-world PG_TEST_EXTRA='kerberos ldap ssl' 2>&1" | tee -a testlog
  su_eval "make $dma_regress_opt polar-check 2>&1" | tee -a testlog
  check_failed_case "check-world"
fi

if [[ $regress_test == "on" ]] && [[ $initpx != "yes" ]];
then
  su_eval "make $dma_regress_opt polar-check 2>&1" | tee -a testlog
  if [ -e ./src/test/regress/regression.diffs ]
  then
    cat ./src/test/regress/regression.diffs
    exit 1
  fi
fi

###################### PHASE 5: init and start ######################
# to protect us from running from wrong dir, use ../polardb_pg etc. here
if [[ $noinit == "no" ]] && [[ "$EUID" == 0 ]];
then
  chown -R $pg_bld_user ../polardb_pg
  chown -R $pg_bld_user $pg_bld_basedir
  chown -R $pg_bld_user $pg_bld_master_dir
fi

if [[ $tde == "on" ]];
then
    tde_initdb_args="--cluster-passphrase-command 'echo \"adfadsfadssssssssfa123123123123123123123123123123123123111313123\"' -e $enc_func"
fi

if [[ $need_initdb == "yes" ]];
then
  su_eval "$pg_bld_basedir/bin/initdb -k -U $pg_db_user -D $pg_bld_master_dir $tde_initdb_args"

  # common configs
  echo "polar_enable_shared_storage_mode = on
        polar_hostid = 1
        max_connections = 100
        polar_wal_pipeline_enable = true
        polar_create_table_with_full_replica_identity = off
        logging_collector = on
        log_directory = 'pg_log'

        unix_socket_directories='.'
        shared_buffers = '2GB'
        synchronous_commit = on
        full_page_writes = off
        #random_page_cost = 1.1
        autovacuum_naptime = 10min
        max_worker_processes = 32
        polar_use_statistical_relpages = off
        polar_enable_persisted_buffer_pool = off
        polar_nblocks_cache_mode = 'all'
        polar_enable_replica_use_smgr_cache = on
        polar_enable_standby_use_smgr_cache = on" >> $pg_bld_master_dir/postgresql.conf

  if [[ $enable_flashback_log == "on" ]];
  then
  echo "polar_enable_flashback_log = on
        polar_enable_fast_recovery_area = on" >> $pg_bld_master_dir/postgresql.conf
  fi

  # echo "max_wal_size = 16GB
  #       min_wal_size = 4GB" >> $pg_bld_master_dir/postgresql.conf

  disk_name=`echo $pg_bld_data_dir | cut -d '/' -f2`

  echo "polar_vfs.localfs_mode = true
  polar_enable_localfs_test_mode = on
  polar_enable_shared_storage_mode = on
  listen_addresses = '*'
  polar_disk_name = '${disk_name}'
  polar_datadir = 'file-dio://${pg_bld_data_dir}'" >> $pg_bld_master_dir/postgresql.conf

  echo "shared_preload_libraries = '\$libdir/polar_px,\$libdir/polar_vfs,\$libdir/polar_worker,\$libdir/pg_stat_statements,\$libdir/auth_delay,\$libdir/auto_explain,\$libdir/polar_monitor_preload,\$libdir/polar_stat_sql'" >> $pg_bld_master_dir/postgresql.conf

  su_eval "bash $pg_bld_basedir/bin/polar-initdb.sh ${pg_bld_master_dir}/ ${pg_bld_data_dir}/ localfs"

  if [[ $dma == "on" ]];
  then
    echo "polar_logindex_mem_size = 0
          polar_enable_flashback_log = off" >> $pg_bld_master_dir/postgresql.conf
    echo "polar_enable_dma = on
          polar_dma_repl_user = $pg_db_user" >> $pg_bld_master_dir/polar_dma.conf
    su_eval "$pg_bld_basedir/bin/postgres -D $pg_bld_master_dir -p $pg_bld_port -c polar_dma_init_meta=ON -c polar_dma_members_info=\"127.0.0.1:$pg_bld_port@1\""
  fi
fi

# init the config of the replica
if [[ $rep_dir_specified == "no" ]] && [[ -n $pg_bld_replica_dir ]] && [[ $withrep == "yes" ]];
then
  rm -fr $pg_bld_replica_dir

  cp -frp $pg_bld_master_dir $pg_bld_replica_dir

  echo "polar_hostid = 2" >> $pg_bld_replica_dir/postgresql.conf
  echo "synchronous_standby_names='replica1'" >> $pg_bld_master_dir/postgresql.conf

  echo "primary_conninfo = 'host=127.0.0.1 port=$pg_bld_port user=$pg_db_user dbname=postgres application_name=replica1'" >> $pg_bld_replica_dir/recovery.conf
  echo "polar_replica = on" >> $pg_bld_replica_dir/recovery.conf
  echo "recovery_target_timeline = 'latest'" >> $pg_bld_replica_dir/recovery.conf
  echo "primary_slot_name = 'replica1'" >> $pg_bld_replica_dir/recovery.conf

  if [[ -n $extra_conf ]];
  then
    if [[ -f $extra_conf ]];
    then
      cat $extra_conf >> $pg_bld_replica_dir/postgresql.conf
      echo >> $pg_bld_replica_dir/postgresql.conf
    else
      echo "invalid extra conf file : $extra_conf";
      exit 1
    fi
  fi

fi

# init the config of the standby
if [[ $standby_dir_specified == "no" ]] && [[ -n $pg_bld_standby_dir ]] && [[ $withstandby == "yes" ]];
then
  rm -fr $pg_bld_standby_dir

  cp -frp $pg_bld_master_dir $pg_bld_standby_dir

  echo "polar_hostid = 3" >> $pg_bld_standby_dir/postgresql.conf

  if [[ $enable_flashback_log == "on" ]];
  then
  echo "polar_enable_flashback_log = on
      polar_enable_lazy_checkpoint = off" >> $pg_bld_standby_dir/postgresql.conf
  fi

  echo "primary_conninfo = 'host=127.0.0.1 port=$pg_bld_port user=$pg_db_user dbname=postgres application_name=standby1'" >> $pg_bld_standby_dir/recovery.conf
  echo "standby_mode = on" >> $pg_bld_standby_dir/recovery.conf
  echo "recovery_target_timeline = 'latest'" >> $pg_bld_standby_dir/recovery.conf
  echo "primary_slot_name = 'standby1'" >> $pg_bld_standby_dir/recovery.conf

  if [[ -n $extra_conf ]];
  then
    if [[ -f $extra_conf ]];
    then
      cat $extra_conf >> $pg_bld_standby_dir/postgresql.conf
      echo >> $pg_bld_standby_dir/postgresql.conf
    else
      echo "invalid extra conf file : $extra_conf";
      exit 1
    fi
  fi
  
fi

if [[ $noinit == "no" ]];
then
# start master
echo "port = ${pg_bld_port}
      polar_hostid = 100
      full_page_writes = off" >> $pg_bld_master_dir/postgresql.conf

su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_master_dir start -w -c"
fi

# create a replication_slot and start
if [[ $withrep == "yes" ]];
then
  for i in $(seq 1 $repnum)
  do
    if [[ $repnum == "1" ]];
    then
      pg_bld_replica_dir_n=${pg_bld_replica_dir}
    else
      pg_bld_replica_dir_n=${pg_bld_replica_dir}${i}
      su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_replica_dir_n stop -m i || true"
      rm -fr $pg_bld_replica_dir_n
      cp -frp $pg_bld_replica_dir $pg_bld_replica_dir_n
    fi
    pg_bld_rep_port_n=$(($pg_bld_rep_port+$i-1))
    echo "port = $pg_bld_rep_port_n
          polar_hostid = $i" >> $pg_bld_replica_dir_n/postgresql.conf

    if [[ -n $extra_conf ]];
    then
      if [[ -f $extra_conf ]];
      then
        if [[ $pg_bld_replica_dir_n != ${pg_bld_replica_dir} ]]
        then
          cat $extra_conf >> $pg_bld_replica_dir_n/postgresql.conf
          echo >> $pg_bld_replica_dir_n/postgresql.conf
        fi
      else
        echo "invalid extra conf file : $extra_conf";
        exit 1
      fi
    fi

    echo "primary_conninfo = 'host=127.0.0.1 port=$pg_bld_port user=$pg_db_user dbname=postgres application_name=replica${i}'" >> $pg_bld_replica_dir_n/recovery.conf
    echo "primary_slot_name = 'replica${i}'" >> $pg_bld_replica_dir_n/recovery.conf
    # su_eval "env $pg_bld_basedir/bin/psql -h 127.0.0.1 -d postgres -U $pg_db_user -c \"SELECT * FROM pg_create_physical_replication_slot('replica${i}')\""
    su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_replica_dir_n start -w -c"
  done
fi

if [[ $dma == "on" ]];
then
  while true
  do
    $pg_bld_basedir/bin/psql -h 127.0.0.1 -U $pg_db_user -p $pg_bld_port -d postgres -c "do \$\$
     DECLARE
       counter integer := 60;
     BEGIN
       LOOP
         PERFORM 1 where pg_is_in_recovery() = false;
         IF FOUND THEN
           RAISE NOTICE 'became leader';
           EXIT;
         END IF;
         PERFORM pg_sleep(1);
         counter := counter - 1;
         IF counter = 0 THEN
           RAISE EXCEPTION 'became leader timeout';
           EXIT;
         END IF;
       END LOOP;
     END\$\$;"
    if [ $? -eq 0 ]; then
       break;
    else
       echo "retry in 1 second .........."
       sleep 1
    fi
  done
fi

if [[ -n $extra_conf ]];
then
  if [[ -f $extra_conf ]];
  then
    cat $extra_conf >> $pg_bld_master_dir/postgresql.conf
    echo >> $pg_bld_master_dir/postgresql.conf
  else
    echo "invalid extra conf file : $extra_conf";
    exit 1
  fi
fi

if [[ $noinit == "no" ]];
then
su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_master_dir reload"
fi

# create a replication_slot and user $pg_bld_user
if [[ $withrep == "yes" ]];
then
  for i in $(seq 1 $repnum)
  do
    su_eval "env $pg_bld_basedir/bin/psql -h 127.0.0.1 -d postgres -p $pg_bld_port -U $pg_db_user -c \"SELECT * FROM pg_create_physical_replication_slot('replica${i}')\""
    sleep 2
  done
fi

# build standby data dir, then start standby
if [[ $withstandby == "yes" ]];
then
  su_eval "env  $pg_bld_basedir/bin/psql -h 127.0.0.1 -d postgres -p $pg_bld_port -U $pg_db_user -c \"SELECT * FROM pg_create_physical_replication_slot('standby1')\""
  sleep 2
  rm -fr $pg_bld_standby_data_dir
  cp -frp $pg_bld_data_dir $pg_bld_standby_data_dir
  sed -i -E "s/${pg_bld_data_dir//\//\\/}/${pg_bld_standby_data_dir//\//\\/}/" $pg_bld_standby_dir/postgresql.conf
  su_eval "$pg_bld_basedir/bin/pg_ctl -D $pg_bld_standby_dir start -w -c -o '-p $pg_bld_standby_port'"
fi

if [[ $noinit == "no" ]];
then
echo "Following command can be used to connect to PG:"
echo ""
echo su $pg_bld_user -c \"$pg_bld_basedir/bin/psql -h 127.0.0.1 -p $pg_bld_port postgres\"
echo su $pg_bld_user -c \"$pg_bld_basedir/bin/psql -h 127.0.0.1 -p $pg_bld_rep_port postgres\"
echo su $pg_bld_user -c \"$pg_bld_basedir/bin/psql -h 127.0.0.1 -p $pg_bld_standby_port postgres\"
echo ""
fi

######################### PHASE 6 Test: test for polar ###########################
if [[ $initpx == "yes" ]];
then
  px_init
fi

if [[ $regress_test == "on" ]] && [[ $regress_test_quick == "off" ]];
then

  # some cases describe using "polar-ignore" when "make polar-installcheck", for polar model
  su_eval "make installcheck 2>&1" | tee -a testlog

  if [ -e ./src/test/regress/regression.diffs ]
  then
    cat ./src/test/regress/regression.diffs
    cp -frp ./src/test/regress/regression.diffs  ./src/test/regress/regression_installcheck.diffs
  fi

  if [[ $initpx == "yes" ]];
  then
    su_eval "make polar-installcheck-px 2>&1" | tee -a testlog
  else
    su_eval "make polar-installcheck 2>&1" | tee -a testlog
  fi

  if [ -e ./src/test/regress/regression.diffs ]
  then
    cat ./src/test/regress/regression.diffs
    cp -frp ./src/test/regress/regression.diffs   ./src/test/regress/regression_polar.diffs
  fi

  if [[ -e ./src/test/regress/regression_installcheck.diffs ]] || [[ -e ./src/test/regress/regression_polar.diffs ]]
  then
    exit 1
  fi

fi

if [[ $extension_test == "on" ]];
then
  if [[ $contrib_test == "on" ]];
  then
    # make installcheck the extensions
    set +x
    echo "============================"
    echo "Check the contrib extensions:"
    echo "============================"
    supported_extensions=`su_eval "$pg_bld_basedir/bin/psql -h 127.0.0.1 -d postgres -U $pg_db_user -c 'show polar_supported_extensions;' -t"`
    extension_arr=(${supported_extensions//+/ })
    contrib_extension_array=`ls contrib/`
    for i in ${extension_arr[@]};
    do
    if [[ $i =~ plperl || $i =~ plpgsql || $i =~ pltcl ]] ; then
      echo "extensions $i in src/pl has checked already."
    elif [[ $i =~ citext || $i =~ btree_gin || $i =~ btree_gist ]] ; then
      : # intentionally empty statement
      su_eval "make -C contrib/$i installcheck 2>&1 " | tee -a testlog
    elif [[ "${contrib_extension_array[@]}" =~ $i ]] ; then
      su_eval "make -C contrib/$i installcheck 2>&1 " | tee -a testlog
    elif [[ $i =~ "uuid-ossp" ]] ; then
      su_eval "make -C contrib/uuid-ossp installcheck 2>&1 " | tee -a testlog
    fi
    done
    set -x
  fi

  if [[ $pl_test == "on" ]];
  then
    set +x
    echo "============================"
    echo "Check the pl extensions:"
    echo "============================"
    : # intentionally empty statement
    su_eval "make -C src/pl installcheck 2>&1 " | tee -a testlog
    set -x
  fi

  if [[ $external_test == "on" ]];
  then
    set +x
    echo "============================"
    echo "Check the external extensions:"
    echo "============================"
    su_eval "make -C external installcheck 2>&1 " | tee -a testlog
    set -x
  fi

  check_failed_case
fi

if [[ $coverage == "on" ]];
then
  del_cov
fi

if [[ $make_installcheck_world == "on" ]] && [[ $regress_test_quick == "off" ]];
then
  export PGHOST=$pg_bld_master_dir
  su_eval "make installcheck-world PG_TEST_EXTRA='kerberos ldap ssl' 2>&1" | tee -a testlog
  su_eval "make polar-installcheck 2>&1" | tee -a testlog
  check_failed_case "installcheck-world"
  unset PGHOST
fi

if [[ $regress_test_ng == "on" ]]
then
  echo "regress_test_ng begin"
  if [[ $regress_test_quick == "off" ]];
  then
    su_eval "make -C src/test installcheck 2>&1" | tee -a testlog
    su_eval "make -C src/test/regress polar-installcheck 2>&1" | tee -a testlog
    check_failed_case
  else
    killall postgres || true
    killall polar-postgres || true
    unset COPT
    su_eval "make $dma_regress_opt -C src/test check 2>&1" | tee -a testlog
    su_eval "make $dma_regress_opt -C src/test/regress polar-check 2>&1" | tee -a testlog
    check_failed_case
  fi
  echo "regress_test_ng end"
fi

echo "rds build done"
exit 0
