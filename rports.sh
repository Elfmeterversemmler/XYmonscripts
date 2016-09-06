#!/bin/bash

# rports.sh
#
BBPROG=rports.sh; export BBPROG
#
TEST="rports"

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
NC="${BBHOME}/bin/nc"

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
#
# Set variables for all config from config file
#
for CFG in $(get_config_list <(${SED} 's/#.*$//g' ${CFGFILE}))
do
	${RM} -f ${BBTMP}/${CFG}.$$
	unset $(set | ${AWK} -F= '/^rports_/  { print $1 }') rports_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} rports_
	PREFIX=""
	MAXCOLOR="red"
	PPROT=""
	if [ -n "${rports_PREFIX}" ]
	then
		PREFIX="${rports_PREFIX}"
	fi
	if [ -n "${rports_PORTS}" ]
	then
		PORTS="${rports_PORTS}"
	fi
	if [ -n "${rports_MAXCOLOR}" ]
	then
		MAXCOLOR="${rports_MAXCOLOR}"
	fi
	PORTS=$(echo "${rports_PORTS}"|${SED} 's/,/ /g')
	for PORT in ${PORTS}
	do
		PNUMB=$(echo "${PORT}"|${AWK} -F\: '{print $1}')
		PNAME=$(echo "${PORT}"|${AWK} -F\: '{print $2}')
		RHOST=$(echo "${PORT}"|${AWK} -F\: '{print $3}')
		PPROT=$(echo "${PORT}"|${AWK} -F\: '{print $4}')
		if [ "${PPROT}" = "U" ]
		then
			PPROT="-u"
		fi
		if ${NC} -z ${PPROT} ${RHOST} ${PNUMB} >/dev/null
		then
			echo "&green ${PNAME} (${PNUMB}) on ${RHOST} UP"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
		else
			echo "&${MAXCOLOR} ${PNAME} (${PNUMB}) on ${RHOST} DOWN"|${SED} 's/_/ /g' >> ${BBTMP}/${CFG}.$$
		fi
	done

	if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
	then
		COLOR="red"
		STATLINE="remote ports NOT ok"
	elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
	then
		COLOR="yellow"
		STATLINE="remote ports NOT ok"
	else
		COLOR="green"
		STATLINE="remote ports ok"
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.rports ${COLOR} $(date) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"

	${RM} -f ${BBTMP}/${CFG}.$$
done
