#!/bin/bash

TIME_STARTED="`date`"
NUMCORE=$(cat /proc/cpuinfo | grep -c cores)
export NUMCORE

# remove the override from the docker image
dpkg-statoverride --remove /usr/bin/sudo

apt-get update
apt-get -y upgrade
apt-get -y install git lsb-release libpcre3-dev zlib1g-dev build-essential unzip uuid-dev webp g++ libssl-dev wget curl sudo rsync gperf

DIST=$(lsb_release -c -s)
apt-get -y -t ${DIST}-backports upgrade

if [ "$DIST" == "trusty" ]; then
    apt-get install binutils-2.26
    export PATH="/usr/lib/binutils-2.26/bin:$PATH"
fi

# Don't mind the errors, one way or the other we will get python2 installed :-)
apt-get -y install python-minimal
apt-get -y install python2-minimal
rm -f /usr/bin/python
ln -s /usr/bin/python2 /usr/bin/python

# Install depot tools
mkdir -p ~/bin
cd ~/bin
git clone --depth=1 -c advice.detachedHead=false https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH=$PATH:~/bin/depot_tools

cd /usr/src/incubator-pagespeed-mod

# Remove output from last compile
rm -rf psol

#
# Jammy has new glibc, which has removed some functions. After altering the files below please clone git
# again before building for older glibs, as these changes are probably not compatible with older builds.
#
if [ "$DIST" == "jammy" ]; then
    sed -i -r 's/sys_siglist\[signum\]/strsignal(signum)/g' third_party/apr/src/threadproc/unix/signals.c
    sed -i s/"pthread_mutex_consistent_np"/"pthread_mutex_consistent"/g third_party/apr/src/locks/unix/proc_mutex.c
    sed -i s/"define HAVE_PTHREAD_YIELD 1"/"define HAVE_PTHREAD_YIELD 0"/g third_party/apr/gen/arch/linux/x64/include/apr_private.h
fi

# Finally! build psol! Get some coffee and let the magic do it's job
python build/gyp_chromium --depth=.
tail -F /usr/src/incubator-pagespeed-mod/log/install_deps.log &
make -j${NUMCORE} BUILDTYPE=Release mod_pagespeed_test pagespeed_automatic_test
tail -F /usr/src/incubator-pagespeed-mod/log/psol_automatic_build.log &
install/build_psol.sh --skip_tests

rm /usr/src/incubator-pagespeed-mod/log/install_deps.log
rm /usr/src/incubator-pagespeed-mod/log/psol_automatic_build.log

echo "Crunching psol.tar.xz with -9e --threads=${NUMCORE}"
XZ_OPT="-9e --threads=${NUMCORE}" tar cJf /usr/src/psol-${DIST}.tar.xz psol/

TIME_ENDED="`date`"

echo "Finished!"
echo "Started: ${TIME_STARTED}"
echo "Ended:   ${TIME_ENDED}"
echo "Cores:   ${NUMCORE}"
echo "Dumped psol.tar.xz as /usr/src/psol-${DIST}.tar.xz"
echo "--------------------------------------------------> The End"
echo ""

exit 0;

