#!/bin/bash

# logger.sh
#
BBPROG=logger.sh; export BBPROG
#
TEST="logger"

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

if [ -x "/usr/bin/perl" ]
then
	PERL="/usr/bin/perl"
else
	PERL="/usr/local/bin/perl"
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
	unset $(set | ${AWK} -F= '/^logger_/  { print $1 }') logger_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} logger_
	GLOBSTART=$((10#$(echo ${logger_BASETIME}|${AWK} -F\, '{print $1}'|${AWK} -F\- '{print $1}')))
	GLOBSTOPP=$((10#$(echo ${logger_BASETIME}|${AWK} -F\, '{print $1}'|${AWK} -F\- '{print $2}')))
	GLOBDAYS=$((10#$(echo ${logger_BASETIME}|${AWK} -F\, '{print $2}')))
	TIME=$((10#$(${DATE} +%H%M)))
	MAXCOLOR="red"
	MTOIGN="NULL"
	ERRORS=""
	WARNINGS=""
	PREFIX=""
	SOLUTION=""
	ROTATE="manual"
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
	if [ -n "${logger_PREFIX}" ]
	then
		PREFIX="${logger_PREFIX}"
	fi
	if [ -n "${logger_MAXCOLOR}" ]
	then
		MAXCOLOR="${logger_MAXCOLOR}"
	fi
	if [ -n "${logger_SOLMSG}" ]
	then
		SOLUTION="${logger_SOLMSG}"
	fi
	if [ -n "${logger_ROTATE}" ]
	then
		ROTATE="${logger_ROTATE}"
	fi
	if [ -n "${logger_IGNORE}" ]
	then
		MTOIGN=$(echo "${logger_IGNORE}"|${SED} 's/,/\|/g')
	fi
	if [ -n "${logger_ERRORS}" ]
	then
		ERRORS=$(echo "${logger_ERRORS}"|${SED} 's/,/\|/g')
	fi
	if [ -n "${logger_WARNINGS}" ]
	then
		WARNINGS=$(echo "${logger_WARNINGS}"|${SED} 's/,/\|/g')
	fi
	if [[ ${TIME} -le ${GLOBSTART} || ${TIME} -gt ${GLOBSTOPP} ]] || mondays ${GLOBDAYS}
	then
		echo "&green Outside monitoring hours ($(echo "${logger_BASETIME}"|${SED} 's/5$/ Mon-Fri/g'))" > ${BBTMP}/${CFG}.$$
	else
		LOGFILES=$(echo "${logger_LOGFILES}"|${SED} 's/,/ /g')
		for LOGFILE in ${LOGFILES}
		do
			echo >> ${BBTMP}/${CFG}.$$
			echo "<h3><u> ${logger_BASEDIR}/${LOGFILE} </u></h3>" >> ${BBTMP}/${CFG}.$$
			echo >> ${BBTMP}/${CFG}.$$
			BYTEFILE="$(echo ${logger_BASEDIR}/${LOGFILE}|${SED} 's/\//_/g')"
			if [[ "${ROTATE}" =~ "auto" ]]
			then
				TIMEOUT=$(echo "${ROTATE}"|${AWK} -F\, '{print $2}')
				if [ "${TIMEOUT}" = "" ]
				then
					LUPDATETIMEOUT=30
				fi
				TOSECONDS=$((TIMEOUT*60))
				NOW=$(${PERL} -MPOSIX -e 'print time()')
				MINELAPSED=$((NOW - TOSECONDS))
				if [ -s ${BBTMP}/${BYTEFILE}.error ]
				then
					LUPDATEERRFILE=$($PERL} -MPOSIX -e 'print((stat shift)[9])' ${BBTMP}/${BYTEFILE}.error )
					if [ ${MINELAPSED} -gt ${LUPDATEERRFILE} ]
					then
						${RM} ${BBTMP}/${BYTEFILE}.error
					fi
				fi
				if [ -s ${BBTMP}/${BYTEFILE}.warning ]
				then
					LUPDATEWARFILE=$(${PERL} -MPOSIX -e 'print((stat shift)[9])' ${BBTMP}/${BYTEFILE}.warning )
					if [ ${MINELAPSED} -gt ${LUPDATEWARFILE} ]
					then
						${RM} ${BBTMP}/${BYTEFILE}.warning
					fi
				fi
			fi
			if [[ -f "${logger_BASEDIR}/${LOGFILE}" && -r "${logger_BASEDIR}/${LOGFILE}" ]]
			then
				if [ -s "${BBTMP}/${BYTEFILE}" ]
				then
					LASTBYTES=$(${CAT} ${BBTMP}/${BYTEFILE} 2>/dev/null)
				else
					LASTBYTES="0"
				fi
				ACTBYTES=$(${LS} -og ${logger_BASEDIR}/${LOGFILE}|${AWK} '{print $3}')
				DIFFBYTES=$((ACTBYTES-LASTBYTES))
				if [ ${DIFFBYTES} -lt 0 ]
				then
					DIFFBYTES=${ACTBYTES}
				fi
				if [ "${ERRORS}" != "" ]
				then
					${TAIL} -c ${DIFFBYTES} ${logger_BASEDIR}/${LOGFILE}|${EGREP} "${ERRORS}"|${EGREP} -v "${MTOIGN}"|${SED} 's/^.*$/\&'"${MAXCOLOR}"' &/g' >> ${BBTMP}/${BYTEFILE}.error
				fi
				if [ "${WARNINGS}" != "" ]
				then
					${TAIL} -c ${DIFFBYTES} ${logger_BASEDIR}/${LOGFILE}|${EGREP} "${WARNINGS}"|${EGREP} -v "${MTOIGN}"|${SED} 's/^.*$/\&yellow &/g' >> ${BBTMP}/${BYTEFILE}.warning
				fi
				echo ${ACTBYTES} > ${BBTMP}/${BYTEFILE}
			elif [[ ! -f "${logger_BASEDIR}/${LOGFILE}" || ! -r "${logger_BASEDIR}/${LOGFILE}" ]]
			then
				echo "&red ${logger_BASEDIR}/${LOGFILE} not accessible" >> ${BBTMP}/${CFG}.$$
			fi
			${CAT} ${BBTMP}/${BYTEFILE}.error >> ${BBTMP}/${CFG}.$$ 2>/dev/null
			${CAT} ${BBTMP}/${BYTEFILE}.warning >> ${BBTMP}/${CFG}.$$ 2>/dev/null
		done
			
		if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
		then
			COLOR="red"
			STATLINE="possible logfile problems"
			echo "${SOLUTION}" >> ${BBTMP}/${CFG}.$$ 2>/dev/null
		elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
		then
			COLOR="yellow"
			STATLINE="possible logfile problems"
			echo "${SOLUTION}" >> ${BBTMP}/${CFG}.$$ 2>/dev/null
		else
			COLOR="green"
			STATLINE="no logfile problems"
		fi
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.${CFG} ${COLOR} $(date) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"

	${RM} -f ${BBTMP}/${CFG}.$$
done
