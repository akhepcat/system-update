#!/bin/bash
PROG="${0##*/}"
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
DO_RETURN=${SHLVL}

#############################

do_exit()
{
        STATUS=${1:-0}
        REASON=${2}

        [[ -n "${REASON}" ]] && echo "${REASON}"

        [[ ${DO_RETURN} -eq 1 ]] && return $STATUS || exit $STATUS
}

usage() {
        echo "$PROG -f [-v ###] [-d distro] [-h]"
	echo -e "\t -v \t download specific version"
	echo -e "\t -d \t download different kernel distro build than running"
	echo -e "\t -f \t force exact revision selected by -v"
	echo -e "\t -h \t this help"

        do_exit 1
}

ROUTE="$(ip -4 route show default scope global)"


KERV=$(dpkg -l linux-firmware firmware-linux | grep ii | awk '{print $3}')
MACH=$(uname -m)
ARCH=$(uname -i)
ARCH=${ARCH//unknown/$MACH}
ARCH=${ARCH//x86_64/amd64}
ARCH=${ARCH//i686/i386}
ARCH=${ARCH//armv6l/armhf}

httpproxy=$(apt-config dump 2>&1 | grep Acquire::http::Proxy | cut -f 2 -d\")
socksproxy=$(apt-config dump 2>&1 | grep  Acquire::socks::Proxy | cut -f 2 -d\")

PROXY="${httpproxy:-$socksproxy}"
[[ -n "${PROXY}" ]] &&cCPROXY="--proxy ${PROXY}"

#########################################
FORCE=${KERV%%-*}
VERSION=0
DISTRO=trusty

while getopts "v:fhd:" param; do
 case $param in
  f) FORCED="yes" ;;
  d) DISTRO=${OPTART} ;;
  v) VERSION=${OPTARG} ;;
  h) usage ;;
  *) echo "Invalid option detected"; usage ;;
 esac
done 

# Override the current system with the cached version
OREL=$(lsb_release -c|cut -f 2 -d:)
OREL=${OREL//[	 ]/}
[[ -r ~/.kernupd ]] && LASTREL="$(awk '{print $1}' ~/.kernupd)"
RELEASE=${LASTREL:-$OREL}
RELEASE=${DISTRO:-$RELEASE}

SITE="https://launchpad.net/ubuntu/${DISTRO}/+package/linux-firmware"

[[ -z "${ROUTE}" ]] && do_exit 1 "No network connection"

if [[ -n "${FORCED}" ]]
then
	FORCE=${VERSION}
	echo "Checking for new firmware v${VERSION} for release ${RELEASE}"
	FILTER=""
else
	echo "Checking for firmware newer than v${KERV} release ${RELEASE}"
	FILTER="-v"
fi

# curl returns:  <a href="/ubuntu/saucy/amd64/linux-firmware/1.116">
PAGE=$(curl ${CPROXY} -stderr /dev/null ${SITE} | grep -i "${RELEASE}/${ARCH}/linux-firmware/" | tail -1 | grep -v ${KERV:-zzzzzzzzx} | cut -f 2 -d\")
#PAGE="${PAGE##*href=\"}"
#PAGE="${PAGE%%/\">v*}"

if [[ -n "${PAGE}" ]]
then
	# curl returns: href="http://launchpadlibrarian.net/152063438/linux-firmware_1.116_all.deb">linux-firmware_1.116_all.deb</a>
        FILES=$(curl ${CPROXY} -stderr /dev/null https://launchpad.net/${PAGE}/ | grep -E "(all|$ARCH).deb" | grep ${FILTER} "${FORCE}" | cut -f 2 -d\" )

        [[ -n "${FILES}" ]] && \
                for file in ${FILES}
                do
                	echo "retrieving ${file}"
                        curl ${CPROXY} --remote-name  ${file}
                done
fi
