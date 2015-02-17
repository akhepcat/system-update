#!/bin/bash
PROG="${0##*/}"

usage() {
        echo "$PROG -f [-r ###] [-d distro] [-lLh]"
	echo -e "\t -r \t download different kernel revision than running"
	echo -e "\t -d \t download different kernel distro build than running"
	echo -e "\t -f \t force exact revision selected by -r"
	echo -e "\t -L \t list available distros"
	echo -e "\t -l \t list available versions"
	echo -e "\t -h \t this help"

        exit 1
}

# non-variable variables
SITE="http://kernel.ubuntu.com/~kernel-ppa/mainline/"
KERV=$(uname -r)
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
if [ -n "${PROXY}" ]
then
	CPROXY="--proxy ${PROXY}"
fi


list_distros() {
	echo "Fetching current list..."
	curl -s --fail ${CPROXY} ${SITE} 2>&1 | grep -i v3 | sed 's/.*href="v3/v3/g' | cut -f 1 -d \" | sed 's/.*-\([a-z]*\)\/$/\1/' | sort -u
	exit 0
}

list_versions() {
	VERSION=$1
	echo "Fetching current list..."
	curl -s --fail ${CPROXY} ${SITE} 2>&1 | grep -iE "v[0-9\.]*-${VERSION}" | sed 's/.*href="v3/v3/g' | cut -f 1 -d \" | sed 's/v\(3.*\)-.*\/$/\1/' | sort -u
	exit 0
}

#########################################
FORCE=${KERV%%-*}

while getopts ":r:d:fhl" param; do
 case $param in
  f) FORCED="yes" ;;
  r) VERSION=${OPTARG} ;;
  d) DISTRO=${OPTARG} ;;
  h) usage ;;
  l) DO_LIST_VERSIONS=1 ;;
  L) list_distros ;;
  *) echo "Invalid option detected"; usage ;;
 esac
done 

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

if [ -n "${DO_LIST_VERSIONS}" ]
then
	# we fall through all the way to here so we know what version to look for.
	list_versions ${RELEASE}
	exit 0
fi

if [ -n "${FORCED}" ]
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


if [ -z "${FORCED}" -a $SUB -gt $NSUB ]
then
	exit 1
fi

if [ -n "${PAGE}" ]
then
        FILEPAGE=${SITE}${PAGE}
        FILES=$(curl ${CPROXY} -stderr /dev/null ${FILEPAGE}/ | grep -E "(all|$ARCH).deb" | grep -v "virtual" | grep ${FILTER} "${FORCE}" | grep ${LATENCY} | sed 's/<tr>.*href="//g; s/">.*$//g;' )

        if [ -n "${FILES}" ]
        then
                for file in ${FILES}
                do
                	echo "retrieving ${FILEPAGE}/${file}"
                        curl ${CPROXY} --remote-name  ${FILEPAGE}/${file}
                done
		test $? && echo "${RELEASE}" > ~/.kernupd
	fi
fi
