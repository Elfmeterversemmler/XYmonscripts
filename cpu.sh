#!/bin/bash

# cpu.sh
#
BBPROG=cpu.sh; export BBPROG
#
TEST="cpu"

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
# Function : mondays value
# Purpose  : check if today is a monitored day
mondays()
{
	DAYS="${1}"
	WDAY=$(${DATE} +%w)
	if [ ${DAYS} -eq 5 ]
	then
		if [ ${WDAY} -eq 6 -o ${WDAY} -eq 0 ]
		then
			return 0
		else
			return 1
		fi
	else
		return 1
	fi
}
#
# Set variables for all config from config file
#
for CFG in $(get_config_list <(${SED} 's/#.*$//g' ${CFGFILE}))
do
	${RM} -f ${BBTMP}/${CFG}.$$
	unset $(set | ${AWK} -F= '/^cpu_/  { print $1 }') cpu_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} cpu_
	GLOBSTART=$((10#$(echo ${cpu_BASETIME}|${AWK} -F\, '{print $1}'|${AWK} -F\- '{print $1}')))
	GLOBSTOPP=$((10#$(echo ${cpu_BASETIME}|${AWK} -F\, '{print $1}'|${AWK} -F\- '{print $2}')))
	GLOBDAYS=$((10#$(echo ${cpu_BASETIME}|${AWK} -F\, '{print $2}')))
	TIME=$((10#$(${DATE} +%H%M)))
	PREFIX=""
	CPUVALUES="${cpu_CPUVALUES}"
	if [ -n "${cpu_PREFIX}" ]
	then
		PREFIX="${cpu_PREFIX}"
	fi
	if [ -z "${cpu_CPUVALUES}" ]
	then
		CPUVALUES="1.0:2.0"
	fi
	if [ -z "${GLOBSTART}" ]
	then
		GLOBSTART="0000"
	fi
	if [ -z "${GLOBSTOPP}" ]
	then
		GLOBSTOPP="2359"
	fi
	if [ -z "${GLOBDAYS}" ]
	then
		GLOBDAYS="7"
	fi

	CPUWARN=$(echo "${CPUVALUES}"|${AWK} -F\: '{print $1}')
	CPUPANIC=$(echo "${CPUVALUES}"|${AWK} -F\: '{print $2}')
	CPUAVG=$(echo "$(${UPTIME})"|${AWK} '{print $(NF-1)}'|${SED} 's/,//g')

	if [[ ${TIME} -le ${GLOBSTART} || ${TIME} -gt ${GLOBSTOPP} ]] || mondays ${GLOBDAYS}
	then
		echo "&green Outside monitoring hours ($(echo "${cpu_BASETIME}"|${SED} 's/5$/ Mon-Fri/g'))" > ${BBTMP}/${CFG}.$$
	else
		CPUW100=$(echo "${CPUWARN} * 100 / 1"|${BC})
		CPUP100=$(echo "${CPUPANIC} * 100 / 1"|${BC})
		CPUA100=$(echo "${CPUAVG} * 100 / 1"|${BC})
		if [ ${CPUA100} -ge ${CPUP100} ]
		then
			echo "&red Load is CRITICAL - ${CPUAVG}" > ${BBTMP}/${CFG}.$$
		elif [ ${CPUA100} -ge ${CPUW100} ]
		then
			echo "&yellow Load is HIGH - ${CPUAVG}" > ${BBTMP}/${CFG}.$$
		else
			echo "&green Load is ok - ${CPUAVG}" > ${BBTMP}/${CFG}.$$
		fi
	fi

	if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
	then
		COLOR="red"
		STATLINE="cpu load too high"
	elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
	then
		COLOR="yellow"
		STATLINE="cpu load high"
	else
		COLOR="green"
		STATLINE="cpu load ok"
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.cpu ${COLOR} $(date) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"

	${RM} -f ${BBTMP}/${CFG}.$$
done
