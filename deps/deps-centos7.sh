#!/bin/bash
# 
# The script is based on a clean CentOS 7 system.
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

# Executed by root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Not running as root"
    exit
fi

# avoid missing locale
sed -i 's/override_install_langs/# &/' /etc/yum.conf
# for su postgres
sed -i 's/4096/unlimited/g' /etc/security/limits.d/20-nproc.conf

# extra yum software source
# curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
# curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
rpmkeys --import file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
yum install -y epel-release centos-release-scl
rpmkeys --import file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
rpmkeys --import file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
yum update -y

# compile tools
yum install -y \
    devtoolset-9-gcc \
    devtoolset-9-gcc-c++ \
    devtoolset-9-gdb \
    devtoolset-9-libstdc++-devel \
    devtoolset-9-make \
    llvm-toolset-7.0-llvm-devel \
    llvm-toolset-7.0-clang-devel \
    cmake3

# dependencies
yum install -y \
    libicu-devel \
    pam-devel \
    readline-devel \
    libxml2-devel \
    libxslt-devel \
    openldap-devel \
    openldap-clients \
    openldap-servers \
    openssl-devel \
    libuuid-devel \
    xerces-c-devel \
    bison \
    flex \
    gettext \
    tcl-devel \
    python-devel \
    perl-IPC-Run \
    perl-Expect \
    perl-Test-Simple \
    perl-DBD-Pg \
    perl-ExtUtils-Embed \
    perl-ExtUtils-MakeMaker \
    zlib-devel \
    krb5-devel \
    krb5-workstation \
    krb5-server \
    protobuf-devel \
    libaio-devel \
    fuse-devel

ln /usr/lib64/perl5/CORE/libperl.so /usr/lib64/libperl.so

# yum install -y
#     git lcov psmisc sudo vim \
#     less \
#     net-tools \
#     python2-psycopg2 \
#     python2-requests \
#     tar \
#     shadow-utils \
#     which  \
#     binutils\
#     libtool \
#     perf \
#     make sudo \
#     wget \
#     util-linux

# enable GCC9 and LLVM7
echo "source /opt/rh/devtoolset-9/enable" >> /etc/bashrc && \
echo "source /opt/rh/llvm-toolset-7.0/enable" >> /etc/bashrc && \
ln -s /usr/bin/cmake3 /usr/bin/cmake
source /etc/bashrc

# install Node.js repo
# curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
# install Yarn
# curl -sL https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo && \
#     yum install -y yarn

GITHUB_PROXY=
# GITHUB_PROXY=https://ghproxy.com

cd /usr/local

ZLOG_VERSION=1.2.14
PFSD_VERSION=pfsd4pg-release-1.2.42-20220419

# download zlog for PFSD
wget --no-verbose --no-check-certificate "${GITHUB_PROXY}https://github.com/HardySimpson/zlog/archive/refs/tags/${ZLOG_VERSION}.tar.gz"
# download PFSD
wget --no-verbose --no-check-certificate "${GITHUB_PROXY}https://github.com/ApsaraDB/PolarDB-FileSystem/archive/refs/tags/${PFSD_VERSION}.tar.gz"

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
rm -rf PolarDB-FileSystem-$PFSD_VERSION* && \
ldconfig
