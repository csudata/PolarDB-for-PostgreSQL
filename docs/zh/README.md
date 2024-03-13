---
home: true
title: 文档
heroImage: /images/polardb.png
footer: Apache 2.0 Licensed | Copyright © Alibaba Group, Inc.
---

---

### 通过 Docker 快速使用

从 DockerHub 上拉取 PolarDB for PostgreSQL 的 [本地存储实例镜像](https://hub.docker.com/r/polardb/polardb_pg_local_instance/tags)，创建并运行容器，然后直接试用 PolarDB-PG：

```bash:no-line-numbers
# 拉取 PolarDB-PG 镜像
docker pull polardb/polardb_pg_local_instance
# 创建并运行容器
docker run -it --rm polardb/polardb_pg_local_instance psql
# 测试可用性
postgres=# SELECT version();
            version
--------------------------------
 PostgreSQL 11.9 (POLARDB 11.9)
(1 row)
```

<div class="features">

  <div class="feature">
    <h3>部署指南</h3>
    <ul style="position: relative;z-index: 10;">
      <li><a href="./deploying/introduction.html">架构简介</a></li>
      <li><a href="./deploying/quick-start.html">快速部署</a></li>
      <li><a href="./deploying/deploy.html">进阶部署</a></li>
      <!-- <li><a href="./deploying/storage-aliyun-essd.html">存储设备的准备</a></li>
      <li><a href="./deploying/fs-pfs.html">文件系统的准备</a></li>
      <li><a href="./deploying/db-localfs.html">编译部署 PolarDB 内核</a></li> -->
      <li><a href="./deploying/deploy-stack.html">更多部署方式</a></li>
    </ul>
  </div>

  <div class="feature">
    <h3>使用与运维</h3>
    <ul style="position: relative;z-index: 10;">
      <li><a href="./operation/backup-and-restore.html">备份恢复</a></li>
      <li><a href="./operation/tpcc-test.html">TPC-C 测试</a></li>
      <li><a href="./operation/tpch-test.html">TPC-H 测试</a></li>
    </ul>
  </div>

  <div class="feature">
    <h3>自研功能</h3>
    <ul style="position: relative;z-index: 10;">
      <li><a href="./features/v11/performance/">高性能</a></li>
      <li><a href="./features/v11/availability/">高可用</a></li>
      <li><a href="./features/v11/security/">安全</a></li>
      <li><a href="./features/v11/epq/">弹性跨机并行查询（ePQ）</a></li>
      <li><a href="./features/v11/extensions/">第三方插件</a></li>
    </ul>
  </div>

  <div class="feature">
    <h3>原理解读</h3>
    <ul style="position: relative;z-index: 10;">
      <li><a href="./theory/arch-overview.html">特性总览</a></li>
      <li><a href="./theory/buffer-management.html">缓冲区管理</a></li>
      <li><a href="./theory/ddl-synchronization.html">DDL 同步</a></li>
      <li><a href="./theory/logindex.html">LogIndex</a></li>
      <li><a href="./theory/analyze.html">ANALYZE 源码解读</a></li>
    </ul>
  </div>

  <div class="feature">
    <h3>上手开发</h3>
    <ul style="position: relative;z-index: 10;">
      <li><a href="./development/dev-on-docker.html">基于 Docker 容器开发</a></li>
      <li><a href="./development/customize-dev-env.html">定制开发环境</a></li>
    </ul>
  </div>

  <div class="feature">
    <h3>社区贡献</h3>
    <ul style="position: relative;z-index: 10;">
      <li><a href="./contributing/contributing-polardb-docs.html">贡献文档</a></li>
      <li><a href="./contributing/contributing-polardb-kernel.html">贡献代码</a></li>
      <li><a href="./contributing/coding-style">编码风格</a></li>
    </ul>
  </div>

</div>
