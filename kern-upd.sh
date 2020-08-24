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
	echo -e "\t -R \t allow release-candidate versions"
	echo -e "\t -D \t debug what would be done"
	echo -e "\t -3 \t force i386 (32-bit) mode"
	echo -e "\t -6 \t force amd64 (64-bit) mode"
	echo -e "\t -h \t this help"

	do_exit 1
}

list_distros() {
	echo "Fetching current list of distros..."
	curl -s --fail ${CPROXY} ${SITE} 2>&1 | grep -i 'v[34]' | sed 's/.*href="\(v[34]\)/\1/g' | cut -f 1 -d \" | sed 's/.*-\([a-z]*\)\/$/\1/' | sort -u
	do_exit 0
}

list_versions() {
	DISTRO=$1
	echo "Fetching current list of kernels for ${DISTRO}..."
	if [ -n "${RCOK}" ]
	then
		RCYN=SHOWRC
	else
		RCYN=""
	fi
	curl -s --fail ${CPROXY} ${SITE} 2>&1 | grep -iE "v[0-9\.]*-${DISTRO}" | sed 's/.*href="\(v[34]\)/\1/g' | cut -f 1 -d \" | sed "s/v\([34].*\)-${RCYN}.*\/$/\1/" | grep "${VERSION:-.}" | sort -u
	do_exit 0
}

distro_version() {
	local DISTRO=$1

	OREL=$(lsb_release -c|cut -f 2 -d:)
	OREL=${OREL//[	 ]/}

	LASTREL="$(test -e ~/.kernupd && awk '{print $1}' ~/.kernupd)"
	RELEASE=${LASTREL:-$OREL}
	RELEASE=${DISTRO:-$RELEASE}
	CURR=${VERSION:-$KERV}

#+ CURR=4.18-rc4
#+ CURR=4.18
#+ MAJ=4
#+ MIN=4
#+ MIN=4
#+ SUB=18
#+ MAJ=4
#+ MIN=4
#+ SUB=18
	CURR=${CURR%%-*}
	DOTS=${CURR//[0-9]/}
	MAJ=${CURR%%.*}
	if [ ${#DOTS} -gt 1 ]
	then
		MIN=${CURR%.*}
		MIN=${MIN#*.}
		SUB=${CURR##*.}
	else
		MIN=${CURR#*.}
		SUB="0"
	fi
	MAJ=${MAJ:-4}
	MIN=${MIN:-0}
	SUB=${SUB:-0}
}

#############################

# non-variable variables
ROUTE="$(ip -4 route show default scope global)"
SITE="https://kernel.ubuntu.com/~kernel-ppa/mainline/"

KERV=$(uname -r)
FORCE=${KERV%%-*}
MACH=$(uname -m)
ARCH=$(uname -i)
ARCH=${ARCH//unknown/$MACH}
ARCH=${ARCH//x86_64/amd64}
ARCH=${ARCH//i686/i386}
ARCH=${ARCH//armv6l/armhf}
ARCH=${ARCH//aarch64/arm64}
LATENCY="-vi lowlatency"

httpproxy=$(apt-config dump 2>&1 | grep Acquire::http::Proxy | cut -f 2 -d\")
socksproxy=$(apt-config dump 2>&1 | grep  Acquire::socks::Proxy | cut -f 2 -d\")
PROXY="${httpproxy:-$socksproxy}"
[[ -n "${PROXY}" ]] && CPROXY="--proxy ${PROXY}"

#########################################

while getopts ":r:d:fhlcRDL36" param; do
 case $param in
  f) FORCED=1 ;;
  r) VERSION=${OPTARG} ;;
  d) DISTRO=${OPTARG} ;;
  R) RCOK="RC" ;;
  c) CONTINUE=1 ;;
  h) usage ;;
  l) DO_LIST_VERSIONS=1 ;;
  L) DO_LIST_DISTROS=1 ;;
  D) DEBUG=1 ;;
  3) ARCH="i386" ;;
  6) ARCH="amd64" ;;
  *) echo "Invalid option detected"; usage ;;
 esac
done 

[[ -z "${ROUTE}" ]] && do_exit 1 "No network connection"

[[ ${DEBUG:-0} -eq 1 ]] && echo "checking for overloaded distro version"
distro_version ${DISTRO}
[[ ${DEBUG:-0} -eq 1 ]] && echo "decided on version ${RELEASE}"

# we fall through all the way to here so we know what version to look for.
[[ -n "${DO_LIST_VERSIONS}" ]] && list_versions ${RELEASE}
[[ -n "${DO_LIST_DISTROS}" ]] && list_distros ${RELEASE}

if [[ ${FORCED:-0} -eq 1 ]]
then
	FORCE=${VERSION}
	echo "Checking for new kernel v${MAJ}.${MIN}.${SUB} for release ${RELEASE}"
	FILTER=""
else
	echo "Checking for next kernel in v${MAJ}.${MIN} train for release ${RELEASE}"
	FILTER="-v"
fi

RCOK=${RCOK:-rc}

#  PAGE=$(curl ${CPROXY} -stderr /dev/null ${SITE} | grep "v${MAJ}\.${MIN}" | grep -v -- '-rc' | grep ${FILTER} "v${MAJ}\.${MIN}\.${SUB}" | tail -1 | grep -i ${RELEASE} )
[[ ${DEBUG:-0} -eq 1 ]] && echo "fetching index for  ${RELEASE}"
PAGE=$(curl ${CPROXY} -stderr /dev/null ${SITE} | grep "v${MAJ}\.${MIN}" | grep -v -- "-${RCOK}" | \
        grep -E ${FILTER} "v${MAJ}\.${MIN}(-${RELEASE}|\.${SUB}|/)" | sed 's/.*href/href/g' | sort -k 5 -t\> | tail -1 | grep -i ${RELEASE} )
PAGE="${PAGE##*href=\"}"
PAGE="${PAGE%%/\">v*}"

NPAGE=${PAGE//-$RELEASE/}
NSUB=${NPAGE##*.}
NSUB=${NSUB%%-*}
NSUB=${NSUB:-0}

# bail out if we're newer than the remote
if [ ${FORCED:-0} -eq 1 -a $SUB -gt $NSUB ]
then
	[[ ${DEBUG:-0} -eq 1 ]] && echo "no newer kernel for ${RELEASE}"
	do_exit 1
fi

if [[ -n "${PAGE}" ]]
then
        FILEPAGE=${SITE}${PAGE}
	[[ ${DEBUG:-0} -eq 1 ]] && echo "loading file list for ${RELEASE}"
        FILES=$(curl ${CPROXY} -stderr /dev/null ${FILEPAGE}/ | \
        	grep -E "(all|$ARCH)\.deb.*<" | grep -v "virtual" | \
        	grep ${FILTER} "${FORCE//-/.*}" | grep ${LATENCY} | sed 's/.*href="//g; s/">.*$//g;' )

        [[ -n "${FILES}" ]] && \
                for file in ${FILES}
                do
			if [[ ${DEBUG:-0} -eq 0 ]]
			then
	                	echo "retrieving ${FILEPAGE}/${file}"
	                	[[ -r "${file##*/}" ]] && SIZE="-C $(wc --bytes ${file##*/} | awk '{print $1}')"
	                	[[ -n "${CONTINUE}" ]] && SIZE=""

				curl ${CPROXY} ${SIZE} --remote-name  ${FILEPAGE}/${file} || FAILED=1
			else
				echo "${FILEPAGE}/${file}"
				FAILED=1	# avoid writing at the end
			fi
                done
	[[ ${FAILED:-0} -eq 0 ]] && echo "${RELEASE}" > ~/.kernupd
fi
