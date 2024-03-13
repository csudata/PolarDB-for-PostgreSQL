# 定制开发环境

## 自行构建开发镜像

DockerHub 上已有构建完毕的开发镜像 [`polardb/polardb_pg_devel`](https://hub.docker.com/r/polardb/polardb_pg_devel/tags) 可供直接使用（支持 `linux/amd64` 和 `linux/arm64` 两种架构）。

另外，我们也提供了构建上述开发镜像的 Dockerfile，从 [Ubuntu 官方镜像](https://hub.docker.com/_/ubuntu/tags) `ubuntu:20.04` 开始构建出一个安装完所有开发和运行时依赖的镜像，您可以根据自己的需要在 Dockerfile 中添加更多依赖。以下是手动构建镜像的 Dockerfile 及方法：

::: details

```dockerfile
FROM ubuntu:20.04
LABEL maintainer="mrdrivingduck@gmail.com"
CMD bash

# Timezone problem
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Upgrade softwares
RUN apt update -y && \
    apt upgrade -y && \
    apt clean -y

# GCC (force to 9) and LLVM (force to 11)
RUN apt install -y \
        gcc-9 \
        g++-9 \
        llvm-11-dev \
        clang-11 \
        make \
        gdb \
        pkg-config \
        locales && \
    update-alternatives --install \
        /usr/bin/gcc gcc /usr/bin/gcc-9 60 --slave \
        /usr/bin/g++ g++ /usr/bin/g++-9 && \
    update-alternatives --install \
        /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-11 60 --slave \
        /usr/bin/clang++ clang++ /usr/bin/clang++-11 --slave \
        /usr/bin/clang clang /usr/bin/clang-11 && \
    apt clean -y

# Generate locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# Dependencies
RUN apt install -y \
        libicu-dev \
        bison \
        flex \
        python3-dev \
        libreadline-dev \
        libgss-dev \
        libssl-dev \
        libpam0g-dev \
        libxml2-dev \
        libxslt1-dev \
        libldap2-dev \
        uuid-dev \
        liblz4-dev \
        libkrb5-dev \
        gettext \
        libxerces-c-dev \
        tcl-dev \
        libperl-dev \
        libipc-run-perl \
        libaio-dev \
        libfuse-dev && \
    apt clean -y

# Tools
RUN apt install -y \
        iproute2 \
        wget \
        ccache \
        sudo \
        vim \
        git \
        cmake && \
    apt clean -y

# set to empty if GitHub is not barriered
# ENV GITHUB_PROXY=https://ghproxy.com/
ENV GITHUB_PROXY=

ENV ZLOG_VERSION=1.2.14
ENV PFSD_VERSION=pfsd4pg-release-1.2.42-20220419

# install dependencies from GitHub mirror
RUN cd /usr/local && \
    # zlog for PFSD
    wget --no-verbose --no-check-certificate "${GITHUB_PROXY}https://github.com/HardySimpson/zlog/archive/refs/tags/${ZLOG_VERSION}.tar.gz" && \
    # PFSD
    wget --no-verbose --no-check-certificate "${GITHUB_PROXY}https://github.com/ApsaraDB/PolarDB-FileSystem/archive/refs/tags/${PFSD_VERSION}.tar.gz" && \
    # unzip and install zlog
    gzip -d $ZLOG_VERSION.tar.gz && \
    tar xpf $ZLOG_VERSION.tar && \
    cd zlog-$ZLOG_VERSION && \
    make && make install && \
    echo '/usr/local/lib' >> /etc/ld.so.conf && ldconfig && \
    cd .. && \
    rm -rf $ZLOG_VERSION* && \
    rm -rf zlog-$ZLOG_VERSION && \
    # unzip and install PFSD
    gzip -d $PFSD_VERSION.tar.gz && \
    tar xpf $PFSD_VERSION.tar && \
    cd PolarDB-FileSystem-$PFSD_VERSION && \
    sed -i 's/-march=native //' CMakeLists.txt && \
    ./autobuild.sh && ./install.sh && \
    cd .. && \
    rm -rf $PFSD_VERSION* && \
    rm -rf PolarDB-FileSystem-$PFSD_VERSION*

# create default user
ENV USER_NAME=postgres
RUN echo "create default user" && \
    groupadd -r $USER_NAME && \
    useradd -ms /bin/bash -g $USER_NAME $USER_NAME -p '' && \
    usermod -aG sudo $USER_NAME

# modify conf
RUN echo "modify conf" && \
    mkdir -p /var/log/pfs && chown $USER_NAME /var/log/pfs && \
    mkdir -p /var/run/pfs && chown $USER_NAME /var/run/pfs && \
    mkdir -p /var/run/pfsd && chown $USER_NAME /var/run/pfsd && \
    mkdir -p /dev/shm/pfsd && chown $USER_NAME /dev/shm/pfsd && \
    touch /var/run/pfsd/.pfsd && \
    echo "ulimit -c unlimited" >> /home/postgres/.bashrc && \
    echo "export PGHOST=127.0.0.1" >> /home/postgres/.bashrc && \
    echo "alias pg='psql -h /home/postgres/tmp_master_dir_polardb_pg_1100_bld/'" >> /home/postgres/.bashrc

ENV PATH="/home/postgres/tmp_basedir_polardb_pg_1100_bld/bin:$PATH"
WORKDIR /home/$USER_NAME
USER $USER_NAME
```

:::

将上述内容复制到一个文件内（假设文件名为 `Dockerfile-PolarDB`）后，使用如下命令构建镜像：

::: tip
💡 请在下面的高亮行中按需替换 `<image_name>` 内的 Docker 镜像名称
:::

```bash:no-line-numbers{2}
docker build --network=host \
    -t <image_name> \
    -f Dockerfile-PolarDB .
```

## 从干净的系统开始搭建开发环境

该方式假设您从一台具有 root 权限的干净的 CentOS 7 操作系统上从零开始，可以是：

- 安装 CentOS 7 的物理机/虚拟机
- 从 CentOS 7 官方 Docker 镜像 `centos:centos7` 上启动的 Docker 容器

### 建立非 root 用户

PolarDB for PostgreSQL 需要以非 root 用户运行。以下步骤能够帮助您创建一个名为 `postgres` 的用户组和一个名为 `postgres` 的用户。

::: tip
如果您已经有了一个非 root 用户，但名称不是 `postgres:postgres`，可以忽略该步骤；但请注意在后续示例步骤中将命令中用户相关的信息替换为您自己的用户组名与用户名。

:::

下面的命令能够创建用户组 `postgres` 和用户 `postgres`，并为该用户赋予 sudo 和工作目录的权限。需要以 root 用户执行这些命令。

```bash
# install sudo
yum install -y sudo
# create user and group
groupadd -r postgres
useradd -m -g postgres postgres -p ''
usermod -aG wheel postgres
# make postgres as sudoer
chmod u+w /etc/sudoers
echo 'postgres ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
chmod u-w /etc/sudoers
# grant access to home directory
chown -R postgres:postgres /home/postgres/
echo 'source /etc/bashrc' >> /home/postgres/.bashrc
# for su postgres
sed -i 's/4096/unlimited/g' /etc/security/limits.d/20-nproc.conf
```

接下来，切换到 `postgres` 用户，就可以进行后续的步骤了：

```bash
su postgres
source /etc/bashrc
cd ~
```

### 依赖安装

在 PolarDB for PostgreSQL 源码库根目录的 `deps/` 子目录下，放置了在各个 Linux 发行版上编译安装 PolarDB 和 PFS 需要运行的所有依赖。因此，首先需要克隆 PolarDB 的源码库。

PolarDB for PostgreSQL 的代码托管于 [GitHub](https://github.com/ApsaraDB/PolarDB-for-PostgreSQL) 上，稳定分支为 `POLARDB_11_STABLE`。如果因网络原因不能稳定访问 GitHub，则可以访问 [Gitee 国内镜像](https://gitee.com/mirrors/PolarDB-for-PostgreSQL)。

:::: code-group
::: code-group-item GitHub

```bash:no-line-numbers
sudo yum install -y git
git clone -b POLARDB_11_STABLE https://github.com/ApsaraDB/PolarDB-for-PostgreSQL.git
```

:::
::: code-group-item Gitee 国内镜像

```bash:no-line-numbers
sudo yum install -y git
git clone -b POLARDB_11_STABLE https://gitee.com/mirrors/PolarDB-for-PostgreSQL
```

:::
::::

源码下载完毕后，使用 `sudo` 执行 `deps/` 目录下的相应脚本 `deps-***.sh` 自动完成所有的依赖安装。比如：

```bash
cd PolarDB-for-PostgreSQL
sudo ./deps/deps-centos7.sh
```
