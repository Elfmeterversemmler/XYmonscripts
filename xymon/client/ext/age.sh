#!/bin/bash

# age.sh
#
BBPROG=age.sh; export BBPROG
#
TEST="age"

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
REFFILE="${BBTMP}/age"

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
	unset $(set | ${AWK} -F= '/^age_/  { print $1 }') age_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} age_
	GLOBSTART=$((10#$(echo ${age_BASETIME}|${AWK} -F\, '{print $1}'|${AWK} -F\- '{print $1}')))
	GLOBSTOPP=$((10#$(echo ${age_BASETIME}|${AWK} -F\, '{print $1}'|${AWK} -F\- '{print $2}')))
	GLOBDAYS=$((10#$(echo ${age_BASETIME}|${AWK} -F\, '{print $2}')))
	TIME=$((10#$(${DATE} +%H%M)))
	PREFIX=""
	if [ -n "${age_PREFIX}" ]
	then
		PREFIX="${age_PREFIX}"
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
	if [[ ${TIME} -le ${GLOBSTART} || ${TIME} -gt ${GLOBSTOPP} ]] || mondays ${GLOBDAYS}
	then
		echo "&green Outside monitoring hours ($(echo "${age_BASETIME}"|${SED} 's/5$/ Mon-Fri/g'))" > ${BBTMP}/${CFG}.$$
	else
		FILES=$(echo "${age_FILES}"|${SED} 's/,/ /g')
		for FILETIME in ${FILES}
		do
			FILE=$(echo "${FILETIME}"|${AWK} -F\: '{print $1}')
			AGE=$(echo "${FILETIME}"|${AWK} -F\: '{print $2}')
			LASTCHAR=$(echo "${AGE: -1}")
			AGETIME=$(echo "${AGE}"|${TR} -d '[:alpha:]')
			case ${LASTCHAR} in
			[0-9]|m)
				TIMESTAMP=$(/bin/date -d "${AGETIME} minutes ago" +%Y%m%d%H%M)
				;;
			h)
				TIMESTAMP=$(/bin/date -d "${AGETIME} hours ago" +%Y%m%d%H%M)
				;;
			d)
				TIMESTAMP=$(/bin/date -d "${AGETIME} days ago" +%Y%m%d%H%M)
				;;
			esac
			${TOUCH} -t ${TIMESTAMP} ${REFFILE}
			if [[ -f ${FILE} ]]
			then
				if [ "${FILE}" -nt "${REFFILE}" ]
				then
					echo "&green ${FILE} up to date" >> ${BBTMP}/${CFG}.$$
				else
					echo "&red ${FILE} outdated" >> ${BBTMP}/${CFG}.$$
				fi
			elif [[ -d ${FILE} ]]
			then
				if [ "$(${LS} -A ${FILE})" ]
				then
					for FFILE in $(${FIND} ${FILE} -maxdepth 1 -type f)
					do
						if [ "${FFILE}" -nt "${REFFILE}" ]
						then
							echo "&green ${FFILE} up to date" >> ${BBTMP}/${CFG}.$$
						else
							echo "&red ${FFILE} outdated" >> ${BBTMP}/${CFG}.$$
						fi
					done
				else
					echo "&green ${FILE} empty" >> ${BBTMP}/${CFG}.$$
				fi
			fi
			${RM} -f ${REFFILE}
		done
	fi

	if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
	then
		COLOR="red"
		STATLINE="some logfiles are outdated"
	elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
	then
		COLOR="yellow"
		STATLINE="some logfiles are not recent"
	else
		COLOR="green"
		STATLINE="all logfiles are recent"
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.age ${COLOR} $(date) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"

	${RM} -f ${BBTMP}/${CFG}.$$
done
