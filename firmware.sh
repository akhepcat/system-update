#!/bin/bash
PROG="${0##*/}"

usage() {
        echo "$PROG -f [-v ###] [-d distro] [-h]"
	echo -e "\t -v \t download specific version"
	echo -e "\t -d \t download different kernel distro build than running"
	echo -e "\t -f \t force exact revision selected by -v"
	echo -e "\t -h \t this help"

        exit 1
}

# non-variable variables
DISTRO=$(lsb_release -c|cut -f 2 -d:)
DISTRO=${DISTRO//[	 ]/}
if [ -r ~/.kernupd ]
then
	# Override the current system with the cached version
	DISTRO=$(cat ~/.kernupd)
fi
SITE="https://launchpad.net/ubuntu/${DISTRO}/+package/linux-firmware"
KERV=$(dpkg -l linux-firmware | grep ii | awk '{print $3}')
MACH=$(uname -m)
ARCH=$(uname -i)
ARCH=${ARCH//unknown/$MACH}
ARCH=${ARCH//x86_64/amd64}
ARCH=${ARCH//i686/i386}
httpproxy=$(apt-config dump 2>&1 | grep Acquire::http::Proxy | cut -f 2 -d\")
socksproxy=$(apt-config dump 2>&1 | grep  Acquire::socks::Proxy | cut -f 2 -d\")
PROXY="${httpproxy:-$socksproxy}"
if [ -n "${PROXY}" ]
then
	CPROXY="--proxy ${PROXY}"
fi

#########################################
FORCE=${KERV%%-*}

while getopts "v:fh" param; do
 case $param in
  f) FORCED="yes" ;;
  v) VERSION=${OPTARG} ;;
  h) usage ;;
  *) echo "Invalid option detected"; usage ;;
 esac
done 

if [ -n "${FORCED}" ]
then
	FORCE=${VERSION}
	echo "Checking for new firmware v${VERSION} for release ${RELEASE}"
	FILTER=""
else
	echo "Checking for firmware newer than v${KERV} release ${RELEASE}"
	FILTER="-v"
fi

# curl returns:  <a href="/ubuntu/saucy/amd64/linux-firmware/1.116">
PAGE=$(curl ${CPROXY} -stderr /dev/null ${SITE} | grep -i "${RELEASE}/${ARCH}/linux-firmware/" | tail -1 | grep -v ${KERV} | cut -f 2 -d\")
#PAGE="${PAGE##*href=\"}"
#PAGE="${PAGE%%/\">v*}"

if [ -n "${PAGE}" ]
then
	# curl returns: href="http://launchpadlibrarian.net/152063438/linux-firmware_1.116_all.deb">linux-firmware_1.116_all.deb</a>
        FILES=$(curl ${CPROXY} -stderr /dev/null https://launchpad.net/${PAGE}/ | grep -E "(all|$ARCH).deb" | grep ${FILTER} "${FORCE}" | cut -f 2 -d\" )

        if [ -n "${FILES}" ]
        then
                for file in ${FILES}
                do
                	echo "retrieving ${file}"
                        curl ${CPROXY} --remote-name  ${file}
                done
	fi
fi
