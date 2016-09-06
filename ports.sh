#!/bin/bash

# ports.sh
#
BBPROG=ports.sh; export BBPROG
#
TEST="ports"

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
NSTAT="/bin/netstat"

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
	unset $(set | ${AWK} -F= '/^ports_/  { print $1 }') ports_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} ports_
	PREFIX=""
	MAXCOLOR="red"
	if [ -n "${ports_PREFIX}" ]
	then
		PREFIX="${ports_PREFIX}"
	fi
	if [ -n "${ports_PORTS}" ]
	then
		PORTS="${ports_PORTS}"
	fi
	if [ -n "${ports_MAXCOLOR}" ]
	then
		MAXCOLOR="${ports_MAXCOLOR}"
	fi
	PORTS=$(echo "${ports_PORTS}"|${SED} 's/,/ /g')
	for PORT in ${PORTS}
	do
		DOWN="no"
		PNUMB=$(echo "${PORT}"|${AWK} -F\: '{print $1}')
		PNAME=$(echo "${PORT}"|${AWK} -F\: '{print $2}')
		PMCOL=$(echo "${PORT}"|${AWK} -F\: '{print $3}')
		PTIME=$(echo "${PORT}"|${AWK} -F\: '{print $4}')
		PSTART=$((10#$(echo ${PTIME}|${AWK} -F\_ '{print $1}'|${AWK} -F\- '{print $1}')))
		PSTOPP=$((10#$(echo ${PTIME}|${AWK} -F\_ '{print $1}'|${AWK} -F\- '{print $2}')))
		PDAYS=$((10#$(echo ${PTIME}|${AWK} -F\_ '{print $2}')))
		TIME=$((10#$(${DATE} +%H%M)))
		if [ -z "${PSTART}" ]
		then
			PSTART="0000"
		fi
		if [ -z "${PSTOPP}" ]
		then
			PSTOPP="2359"
		fi
		if [ -z "${PDAYS}" ]
		then
			PDAYS="7"
		fi
		if [ "$(echo ${PNUMB:0:1})" = "!" ]
		then
			DOWN="yes"
			PNUMB="${PNUMB:1}"
		fi
		if [ "${PNAME}" = "" ]
		then
			SNAME=$(${GREP} -w ${PNUMB}.tcp /etc/services|${TAIL} -1|${AWK} '{print $1}')
			if [ "${SNAME}" = "" ]
			then
				SNAME="unnamed listener @ ${PNUMB}"
			fi
			PNAME="${SNAME}"
		fi
		if [ "${PMCOL}" = "" ]
		then
			PMCOL="${MAXCOLOR}"
		fi
		if [[ ${TIME} -le ${PSTART} || ${TIME} -gt ${PSTOPP} ]] || mondays ${PDAYS}
		then
			echo "&green ${PNAME} @ ${PNUMB} - outside monitoring hours ($(echo "${PTIME}"|${SED} 's/5$/ Mon-Fri/g'))"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
		else
			if ! ${NSTAT} -an|${GREP} -w LISTEN|${GREP} -w ${PNUMB} >/dev/null && [ "${DOWN}" = "yes" ]
			then
				echo "&green ${PNAME} @ ${PNUMB} down"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
			elif ! ${NSTAT} -an|${GREP} -w LISTEN|${GREP} -w ${PNUMB} >/dev/null && [ "${DOWN}" = "no" ]
			then
				echo "&${PMCOL} ${PNAME} @ ${PNUMB} down"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
			elif ${NSTAT} -an|${GREP} -w LISTEN|${GREP} -w ${PNUMB} >/dev/null && [ "${DOWN}" = "yes" ]
			then
				echo "&${PMCOL} ${PNAME} @ ${PNUMB} up"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
			elif ${NSTAT} -an|${GREP} -w LISTEN|${GREP} -w ${PNUMB} >/dev/null && [ "${DOWN}" = "no" ]
			then
				echo "&green ${PNAME} @ ${PNUMB} up"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
			fi
		fi
	done

	if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
	then
		COLOR="red"
		STATLINE="ports NOT ok"
	elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
	then
		COLOR="yellow"
		STATLINE="ports NOT ok"
	else
		COLOR="green"
		STATLINE="ports ok"
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.ports ${COLOR} $(date) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"

	${RM} -f ${BBTMP}/${CFG}.$$
done
