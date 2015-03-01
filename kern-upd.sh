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
        echo "$PROG -f [-r ###] [-d distro] [-lLh]"
	echo -e "\t -r \t download different kernel revision than running"
	echo -e "\t -d \t download different kernel distro build than running"
	echo -e "\t -f \t force exact revision selected by -r"
	echo -e "\t -c \t try to continue/resume aborted downloads"
	echo -e "\t -L \t list available distros"
	echo -e "\t -l \t list available versions"
	echo -e "\t -h \t this help"

	do_exit 1
}

list_distros() {
	echo "Fetching current list..."
	curl -s --fail ${CPROXY} ${SITE} 2>&1 | grep -i v3 | sed 's/.*href="v3/v3/g' | cut -f 1 -d \" | sed 's/.*-\([a-z]*\)\/$/\1/' | sort -u
	do_exit 0
}

list_versions() {
	VERSION=$1
	echo "Fetching current list..."
	curl -s --fail ${CPROXY} ${SITE} 2>&1 | grep -iE "v[0-9\.]*-${VERSION}" | sed 's/.*href="v3/v3/g' | cut -f 1 -d \" | sed 's/v\(3.*\)-.*\/$/\1/' | sort -u
	do_exit 0
}

#############################

# non-variable variables
ROUTE="$(ip -4 route show default scope global)"
SITE="http://kernel.ubuntu.com/~kernel-ppa/mainline/"
KERV=$(uname -r)
FORCE=${KERV%%-*}
OREL=$(lsb_release -c|cut -f 2 -d:)
OREL=${OREL//[	 ]/}
LASTREL="$(test -e ~/.kernupd && awk '{print $1}' ~/.kernupd)"
MACH=$(uname -m)
ARCH=$(uname -i)
ARCH=${ARCH//unknown/$MACH}
ARCH=${ARCH//x86_64/amd64}
ARCH=${ARCH//i686/i386}
httpproxy=$(apt-config dump 2>&1 | grep Acquire::http::Proxy | cut -f 2 -d\")
socksproxy=$(apt-config dump 2>&1 | grep  Acquire::socks::Proxy | cut -f 2 -d\")
PROXY="${httpproxy:-$socksproxy}"
[[ -n "${PROXY}" ]] && CPROXY="--proxy ${PROXY}"

#########################################

while getopts ":r:d:fhlc" param; do
 case $param in
  f) FORCED="yes" ;;
  r) VERSION=${OPTARG} ;;
  d) DISTRO=${OPTARG} ;;
  c) CONTINUE=1 ;;
  h) usage ;;
  l) DO_LIST_VERSIONS=1 ;;
  L) list_distros ;;
  *) echo "Invalid option detected"; usage ;;
 esac
done 

[[ -z "${ROUTE}" ]] && do_exit 1 "No network connection"

RELEASE=${LASTREL:-$OREL}
RELEASE=${DISTRO:-$RELEASE}

CURR=${VERSION:-$KERV}
CURR=${CURR%%-*}
MAJ=${CURR%%.*}
MIN=${CURR%.*}
MIN=${MIN#*.}
SUB=${CURR##*.}
MAJ=${MAJ:-3}
MIN=${MIN:-0}
SUB=${SUB:-0}
LATENCY="-vi lowlatency"

# we fall through all the way to here so we know what version to look for.
[[ -n "${DO_LIST_VERSIONS}" ]] && list_versions ${RELEASE}

if [[ -n "${FORCED}" ]]
then
	FORCE=${VERSION}
	echo "Checking for new kernel v${MAJ}.${MIN}.${SUB} for release ${RELEASE}"
	FILTER=""
else
	echo "Checking for next kernel in v${MAJ}.${MIN} train for release ${RELEASE}"
	FILTER="-v"
fi

#  PAGE=$(curl ${CPROXY} -stderr /dev/null ${SITE} | grep "v${MAJ}\.${MIN}" | grep -v -- '-rc' | grep ${FILTER} "v${MAJ}\.${MIN}\.${SUB}" | tail -1 | grep -i ${RELEASE} )
PAGE=$(curl ${CPROXY} -stderr /dev/null ${SITE} | grep "v${MAJ}\.${MIN}" | grep -v -- '-rc' | \
        grep -E ${FILTER} "v${MAJ}\.${MIN}(-${RELEASE}|\.${SUB})" | tail -1 | grep -i ${RELEASE} )
PAGE="${PAGE##*href=\"}"
PAGE="${PAGE%%/\">v*}"

NPAGE=${PAGE//-$RELEASE/}
NSUB=${NPAGE##*.}
NSUB=${NSUB:-0}

# bail out if we're newer than the remote
if [ -z "${FORCED}" -a $SUB -gt $NSUB ]
then
	do_exit 1
fi

if [[ -n "${PAGE}" ]]
then
        FILEPAGE=${SITE}${PAGE}
        FILES=$(curl ${CPROXY} -stderr /dev/null ${FILEPAGE}/ | grep -E "(all|$ARCH).deb" | grep -v "virtual" | grep ${FILTER} "${FORCE}" | grep ${LATENCY} | sed 's/<tr>.*href="//g; s/">.*$//g;' )

        [[ -n "${FILES}" ]] && \
                for file in ${FILES}
                do
                	echo "retrieving ${FILEPAGE}/${file}"
                	[[ -r "${file##*/}" ]] && SIZE="-C $(wc --bytes ${file##*/} | awk '{print $1}')"
                	[[ -n "${CONTINUE}" ]] && SIZE=""

                        curl ${CPROXY} ${SIZE} --remote-name  ${FILEPAGE}/${file} || FAILED=1
                done
	[[ ${FAILED:-0} -eq 0 ]] && echo "${RELEASE}" > ~/.kernupd
fi
