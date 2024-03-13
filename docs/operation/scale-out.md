---
author: 棠羽
date: 2022/12/19
minute: 30
---

# 计算节点扩缩容

<ArticleInfo :frontmatter=$frontmatter></ArticleInfo>

PolarDB for PostgreSQL 是一款存储与计算分离的数据库，所有计算节点共享存储，并可以按需要弹性增加或删减计算节点而无需做任何数据迁移。所有本教程将协助您在共享存储集群上添加或删除计算节点。

[[toc]]

## 部署读写节点

首先，在已经搭建完毕的共享存储集群上，初始化并启动第一个计算节点，即读写节点，该节点可以对共享存储进行读写。我们在下面的镜像中提供了已经编译完毕的 PolarDB for PostgreSQL 内核和周边工具的可执行文件：

```shell:no-line-numbers
$ docker pull polardb/polardb_pg_binary
$ docker run -it \
    --cap-add=SYS_PTRACE \
    --privileged=true \
    --name polardb_pg \
    --shm-size=512m \
    polardb/polardb_pg_binary \
    bash

$ ls ~/tmp_basedir_polardb_pg_1100_bld/bin/
clusterdb     dropuser           pg_basebackup   pg_dump         pg_resetwal    pg_test_timing       polar-initdb.sh          psql
createdb      ecpg               pgbench         pg_dumpall      pg_restore     pg_upgrade           polar-replica-initdb.sh  reindexdb
createuser    initdb             pg_config       pg_isready      pg_rewind      pg_verify_checksums  polar_tools              vacuumdb
dbatools.sql  oid2name           pg_controldata  pg_receivewal   pg_standby     pg_waldump           postgres                 vacuumlo
dropdb        pg_archivecleanup  pg_ctl          pg_recvlogical  pg_test_fsync  polar_basebackup     postmaster
```

### 确认存储可访问

使用 `lsblk` 命令确认存储集群已经能够被当前机器访问到。比如，如下示例中的 `nvme1n1` 是将要使用的共享存储的块设备：

```shell:no-line-numbers
$ lsblk
NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
nvme0n1     259:0    0   40G  0 disk
└─nvme0n1p1 259:1    0   40G  0 part /etc/hosts
nvme1n1     259:2    0  100G  0 disk
```

### 格式化并挂载 PFS 文件系统

此时，共享存储上没有任何内容。使用容器内的 PFS 工具将共享存储格式化为 PFS 文件系统的格式：

```shell:no-line-numbers
sudo pfs -C disk mkfs nvme1n1
```

格式化完成后，在当前容器内启动 PFS 守护进程，挂载到文件系统上。该守护进程后续将会被计算节点用于访问共享存储：

```shell:no-line-numbers
sudo /usr/local/polarstore/pfsd/bin/start_pfsd.sh -p nvme1n1 -w 2
```

### 初始化数据目录

使用 `initdb` 在节点本地存储的 `~/primary` 路径上创建本地数据目录。本地数据目录中将会存放节点的配置、审计日志等节点私有的信息：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/initdb -D $HOME/primary
```

使用 PFS 工具，在共享存储上创建一个共享数据目录；使用 `polar-initdb.sh` 脚本把将会被所有节点共享的数据文件拷贝到共享存储的数据目录中。将会被所有节点共享的文件包含所有的表文件、WAL 日志文件等：

```shell:no-line-numbers
sudo pfs -C disk mkdir /nvme1n1/shared_data

sudo $HOME/tmp_basedir_polardb_pg_1100_bld/bin/polar-initdb.sh \
    $HOME/primary/ /nvme1n1/shared_data/
```

### 编辑读写节点配置

对读写节点的配置文件 `~/primary/postgresql.conf` 进行修改，使数据库以共享模式启动，并能够找到共享存储上的数据目录：

```ini
port=5432
polar_hostid=1

polar_enable_shared_storage_mode=on
polar_disk_name='nvme1n1'
polar_datadir='/nvme1n1/shared_data/'
polar_vfs.localfs_mode=off
shared_preload_libraries='$libdir/polar_vfs,$libdir/polar_worker'
polar_storage_cluster_name='disk'

logging_collector=on
log_line_prefix='%p\t%r\t%u\t%m\t'
log_directory='pg_log'
listen_addresses='*'
max_connections=1000
synchronous_standby_names='replica1'
```

编辑读写节点的客户端认证文件 `~/primary/pg_hba.conf`，允许来自所有地址的客户端以 `postgres` 用户进行物理复制：

```:no-line-numbers
host	replication	postgres	0.0.0.0/0	trust
```

### 启动读写节点

使用以下命令启动读写节点，并检查节点能否正常运行：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/pg_ctl -D $HOME/primary start

$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql \
    -p 5432 \
    -d postgres \
    -c 'SELECT version();'
            version
--------------------------------
 PostgreSQL 11.9 (POLARDB 11.9)
(1 row)
```

## 集群扩容

接下来，在已经有一个读写节点的计算集群中扩容一个新的计算节点。由于 PolarDB for PostgreSQL 是一写多读的架构，所以后续扩容的节点只可以对共享存储进行读取，但无法对共享存储进行写入。只读节点通过与读写节点进行物理复制来保持内存状态的同步。

类似地，在用于部署新计算节点的机器上，拉取镜像并启动带有可执行文件的容器：

```shell:no-line-numbers
docker pull polardb/polardb_pg_binary
docker run -it \
    --cap-add=SYS_PTRACE \
    --privileged=true \
    --name polardb_pg \
    --shm-size=512m \
    polardb/polardb_pg_binary \
    bash
```

### 确认存储可访问

确保部署只读节点的机器也可以访问到共享存储的块设备：

```shell:no-line-numbers
$ lsblk
NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
nvme0n1     259:0    0   40G  0 disk
└─nvme0n1p1 259:1    0   40G  0 part /etc/hosts
nvme1n1     259:2    0  100G  0 disk
```

### 挂载 PFS 文件系统

由于此时共享存储已经被读写节点格式化为 PFS 格式了，因此这里无需再次进行格式化。只需要启动 PFS 守护进程完成挂载即可：

```shell:no-line-numbers
sudo /usr/local/polarstore/pfsd/bin/start_pfsd.sh -p nvme1n1 -w 2
```

### 初始化数据目录

在只读节点本地磁盘的 `~/replica1` 路径上创建一个空目录，然后通过 `polar-replica-initdb.sh` 脚本使用共享存储上的数据目录来初始化只读节点的本地目录。初始化后的本地目录中没有默认配置文件，所以还需要使用 `initdb` 创建一个临时的本地目录模板，然后将所有的默认配置文件拷贝到只读节点的本地目录下：

```shell:no-line-numbers
mkdir -m 0700 $HOME/replica1
sudo ~/tmp_basedir_polardb_pg_1100_bld/bin/polar-replica-initdb.sh \
    /nvme1n1/shared_data/ $HOME/replica1/

$HOME/tmp_basedir_polardb_pg_1100_bld/bin/initdb -D /tmp/replica1
cp /tmp/replica1/*.conf $HOME/replica1/
```

### 编辑只读节点配置

编辑只读节点的配置文件 `~/replica1/postgresql.conf`，配置好只读节点的集群标识和监听端口，以及与读写节点相同的共享存储目录：

```ini
port=5432
polar_hostid=2

polar_enable_shared_storage_mode=on
polar_disk_name='nvme1n1'
polar_datadir='/nvme1n1/shared_data/'
polar_vfs.localfs_mode=off
shared_preload_libraries='$libdir/polar_vfs,$libdir/polar_worker'
polar_storage_cluster_name='disk'

logging_collector=on
log_line_prefix='%p\t%r\t%u\t%m\t'
log_directory='pg_log'
listen_addresses='*'
max_connections=1000
```

编辑只读节点的复制配置文件 `~/replica1/recovery.conf`，配置好当前节点的角色（只读），以及从读写节点进行物理复制的连接串和复制槽：

```ini:no-line-numbers
polar_replica='on'
recovery_target_timeline='latest'
primary_conninfo='host=[读写节点所在IP] port=5432 user=postgres dbname=postgres application_name=replica1'
primary_slot_name='replica1'
```

由于读写节点上暂时还没有名为 `replica1` 的复制槽，所以需要连接到读写节点上，创建这个复制槽：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql \
    -p 5432 \
    -d postgres \
    -c "SELECT pg_create_physical_replication_slot('replica1');"
 pg_create_physical_replication_slot
-------------------------------------
 (replica1,)
(1 row)
```

### 启动只读节点

完成上述步骤后，启动只读节点并验证：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/pg_ctl -D $HOME/replica1 start

$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql \
    -p 5432 \
    -d postgres \
    -c 'SELECT version();'
            version
--------------------------------
 PostgreSQL 11.9 (POLARDB 11.9)
(1 row)
```

### 集群功能检查

连接到读写节点上，创建一个表并插入数据：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql -q \
    -p 5432 \
    -d postgres \
    -c "CREATE TABLE t(id INT); INSERT INTO t SELECT generate_series(1,10);"
```

在只读节点上可以立刻查询到从读写节点上插入的数据：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql -q \
    -p 5432 \
    -d postgres \
    -c "SELECT * FROM t;"
 id
----
  1
  2
  3
  4
  5
  6
  7
  8
  9
 10
(10 rows)
```

从读写节点上可以看到用于与只读节点进行物理复制的复制槽已经处于活跃状态：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql -q \
    -p 5432 \
    -d postgres \
    -c "SELECT * FROM pg_replication_slots;"
 slot_name | plugin | slot_type | datoid | database | temporary | active | active_pid | xmin | catalog_xmin | restart_lsn | confirmed_flush_lsn
-----------+--------+-----------+--------+----------+-----------+--------+------------+------+--------------+-------------+---------------------
 replica1  |        | physical  |        |          | f         | t      |         45 |      |              | 0/4079E8E8  |
(1 rows)
```

依次类推，使用类似的方法还可以横向扩容更多的只读节点。

## 集群缩容

集群缩容的步骤较为简单：将只读节点停机即可。

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/pg_ctl -D $HOME/replica1 stop
```

在只读节点停机后，读写节点上的复制槽将变为非活跃状态。非活跃的复制槽将会阻止 WAL 日志的回收，所以需要及时清理。

在读写节点上执行如下命令，移除名为 `replica1` 的复制槽：

```shell:no-line-numbers
$HOME/tmp_basedir_polardb_pg_1100_bld/bin/psql \
    -p 5432 \
    -d postgres \
    -c "SELECT pg_drop_replication_slot('replica1');"
 pg_drop_replication_slot
--------------------------

(1 row)
```
