#!/bin/bash

# disk.sh
#
BBPROG=disk.sh; export BBPROG
#
TEST="disk"

if test "$BBHOME" = ""
then
	echo "BBHOME is not set... exiting"
	exit 1
fi

if test ! "$BBTMP"
then
	. $BBHOME/etc/bbdef.sh
fi

COLOR="green"
STATLINE=""
GREENLINES=""
YELLOWLINES=""
REDLINES=""
BBETC="${BBHOME}/etc"
CFGFILE="${BBETC}/${TEST}.cfg"
BC="/usr/bin/bc"

if [ "x${TR}x" = "xx" ]
then
	TR="/usr/bin/tr"
fi
if [ "$(uname -s)" = "SunOS" ]
then
	AWK="/usr/xpg4/bin/awk"
	EGREP="/usr/xpg4/bin/egrep"
	GREP="/usr/xpg4/bin/grep"
	TAIL="/usr/xpg4/bin/tail"
	DF="/usr/bin/df -k"
	DFCMD="/usr/bin/df -k"
fi

# Function: get_config_list config_file
# Purpose : Print the list of configs from config file
get_config_list()
{
	typeset CONFIG_FILE=$1
	${AWK} -F '[][]' ' NF==3 && $0 ~ /^\[.*\]/ { print $2 }' ${CONFIG_FILE}
}

# Function : set_config_vars config_file config [var_prefix]
# Purpose  : Set variables (optionaly prefixed by var_prefix) from config in config file
set_config_vars()
{
	typeset CONFIG_FILE=$1
	typeset CONFIG=$2
	typeset VAR_PREFIX=$3
	typeset CONFIG_VARS

	CONFIG_VARS=$(
	${AWK} -F= -v Config="${CONFIG}" -v Prefix="${VAR_PREFIX}" '
	BEGIN {
		Config = toupper(Config);
		patternConfig = "\\[" Config "]";
	}
	toupper($0)  ~ patternConfig,(/\[/ && toupper($0) !~ patternConfig)  {
		if (/\[/ || NF <2) next;
		sub(/^[[:space:]]*/, "");
		sub(/[[:space:]]*=[[:space:]]/, "=");
		print Prefix $0;
	} ' ${CONFIG_FILE} )
	eval "${CONFIG_VARS}"
}
# Function : mkint value
# Purpose  : "convert" floating point numbers into integers
mkint()
{
	typeset NUMBER=${1}
	echo "${NUMBER}"|${AWK} -F\. '{print $1}'
}
#
# Set variables for all config from config file
#
for CFG in $(get_config_list <(${SED} 's/#.*$//g' ${CFGFILE}))
do
	${RM} -f ${BBTMP}/${CFG}.$$
	unset $(set | ${AWK} -F= '/^disk_/  { print $1 }') disk_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} disk_
	PREFIX=""
	SHOWMOUNTS=""
	UNITS="%"
	if [ -n "${disk_PREFIX}" ]
	then
		PREFIX="${disk_PREFIX}"
	fi
	if [ -n "${disk_UNITS}" ]
	then
		UNITS="${disk_UNITS}"
	fi
	MOUNTS=$(echo "${disk_MOUNTS}"|${SED} 's/,/ /g')
	for MOUNT in ${MOUNTS}
	do
		DFWARN="90"
		DFPANIC="95"
		if [[ "${MOUNT}" =~ ":" ]]
		then
			DFWARN=$(echo "${MOUNT}"|${AWK} -F\: '{print $2}')
			DFPANIC=$(echo "${MOUNT}"|${AWK} -F\: '{print $3}')
			MNTPOINT=$(echo "${MOUNT}"|${AWK} -F\: '{print $1}')
			RECALC=0
		else
			MNTPOINT=$(echo "${MOUNT}")
			RECALC=1
		fi
		FILESYS=$(${DF} -l ${MNTPOINT}|${GREP} -v "^Filesystem")
		SLICE=$(echo "${FILESYS}"|${AWK} '{print $1}')
		TOTALKB=$(echo "${FILESYS}"|${AWK} '{print $2}')
		USEDKB=$(echo "${FILESYS}"|${AWK} '{print $3}')
		AVAILKB=$(echo "${FILESYS}"|${AWK} '{print $4}')
		CAPACITY=$(echo "${FILESYS}"|${AWK} '{print $5}')
		MNTPNT=$(echo "${FILESYS}"|${AWK} '{print $6}')
		if [ "${MNTPOINT}" != "${MNTPNT}" ]
		then
			continue
		fi
		SHOWMOUNTS="${SHOWMOUNTS} ${MNTPOINT}"
		if [ ${RECALC} -eq 1 ]
		then
			if [ "${UNITS}" = "M" ]
			then
				DFWARN=$(mkint $(echo "${TOTALKB} * 0.1 / 1024"|${BC}))
				DFPANIC=$(mkint $(echo "${TOTALKB} * 0.05 / 1024"|${BC}))
			elif [ "${UNITS}" = "G" ]
			then
				DFWARN=$(mkint $(echo "${TOTALKB} * 0.1 / 1024 / 1024"|${BC}))
				DFPANIC=$(mkint $(echo "${TOTALKB} * 0.05 / 1024 / 1024"|${BC}))
			fi
		fi
		case ${UNITS} in
		%)
			ACTCAP=$(echo "${CAPACITY}"|${TR} -d '%')
			if [ ${ACTCAP} -ge ${DFPANIC} ]
			then
				echo "&red ${MNTPNT} (${CAPACITY} used) has reached the PANIC level (${DFPANIC}%)" >> ${BBTMP}/${CFG}.$$
			elif [ ${ACTCAP} -ge ${DFWARN} ]
			then
				echo "&yellow ${MNTPNT} (${CAPACITY} used) has reached the WARNING level (${DFWARN}%)" >> ${BBTMP}/${CFG}.$$
			fi
			;;
		M)
			if [ ${DFWARN} -lt ${DFPANIC} ]
			then
				DFWARNC=${DFPANIC}
				DFPANICC=${DFWARN}
				DFWARN=${DFPANICC}
				DFPANIC=${DFWARNC}
			fi
			DFWARNKB=$(mkint $(echo "${DFWARN} * 1024"|${BC}))
			DFPANKB=$(mkint $(echo "${DFPANIC} * 1024"|${BC}))
			AVAILABLE=$(mkint $(echo "scale = 0; ${AVAILKB} / 1024"|${BC}))
			if [ ${AVAILKB} -le ${DFPANKB} ]
			then
				echo "&red ${MNTPNT} (${AVAILABLE} MB free) has reached the PANIC level (${DFPANIC} MB)" >> ${BBTMP}/${CFG}.$$
			elif [ ${AVAILKB} -le ${DFWARNKB} ]
			then
				echo "&yellow ${MNTPNT} (${AVAILABLE} MB free) has reached the WARNING level (${DFWARN} MB)" >> ${BBTMP}/${CFG}.$$
			fi
			;;
		G)
			if [ ${DFWARN} -lt ${DFPANIC} ]
			then
				DFWARNC=${DFPANIC}
				DFPANICC=${DFWARN}
				DFWARN=${DFPANICC}
				DFPANIC=${DFWARNC}
			fi
			DFWARNKB=$(mkint $(echo "${DFWARN} * 1024 * 1024"|${BC}))
			DFPANKB=$(mkint $(echo "${DFPANIC} * 1024 * 1024"|${BC}))
			AVAILABLE=$(mkint $(echo "scale = 0; ${AVAILKB} / 1024 / 1024"|${BC}))
			if [ ${AVAILKB} -le ${DFPANKB} ]
			then
				echo "&red ${MNTPNT} (${AVAILABLE} GB free) has reached the PANIC level (${DFPANIC} GB)" >> ${BBTMP}/${CFG}.$$
			elif [ ${AVAILKB} -le ${DFWARNKB} ]
			then
				echo "&yellow ${MNTPNT} (${AVAILABLE} GB free) has reached the WARNING level (${DFWARN} GB)" >> ${BBTMP}/${CFG}.$$
			fi
			;;
		esac
	done
	echo "<br>" >> ${BBTMP}/${CFG}.$$
	if [ "${SHOWMOUNTS}" = "" ]
	then
		echo "&green no file systems mounted to monitor" >> ${BBTMP}/${CFG}.$$
	else
		${DF} -l ${SHOWMOUNTS} >> ${BBTMP}/${CFG}.$$
	fi

	if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
	then
		COLOR="red"
		STATLINE="Filesystems NOT ok"
	elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
	then
		COLOR="yellow"
		STATLINE="Filesystems NOT ok"
	else
		COLOR="green"
		STATLINE="Filesystems ok"
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.disk ${COLOR} $(date) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"

	${RM} -f ${BBTMP}/${CFG}.$$
done
