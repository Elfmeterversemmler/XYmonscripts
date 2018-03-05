#!/bin/bash

# oraprocs.sh
#
BBPROG=oraprocs.sh; export BBPROG
#
TEST="dbprocs"
#
# BBHOME=/home/sean/bb; export BBHOME	# FOR TESTING

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
CONFIG="${BBHOME}/etc/oraprocs.cfg"
PREFIX="APP-"

if [ "$(uname -s)" = "SunOS" ]
then
	PS="/usr/ucb/sparcv9/ps axwe"
fi

${RM} -f ${BBTMP}/${TEST}.$$

for PROCESS in $(${GREP} -w ${MACHINE} ${CONFIG}|${AWK} -F\: '{print $2}'|${SED} 's/ //g')
do
	PROCSS=$(echo ${PROCESS}|${SED} 's/\[/\\\[/;s/\]/\\\]/;s/\$/\\\$/')
	PROCSOLLCNT=$(${GREP} -w ${MACHINE} ${CONFIG}|${GREP} -w ${PROCSS}|${AWK} -F\: '{print $3}'|${SED} 's/ //g')
	PROCNAME=$(${GREP} -w ${MACHINE} ${CONFIG}|${GREP} -w ${PROCSS}|${AWK} -F\: '{print $4}')
	PROCISCNT=$(${PS}|${GREP} -c ${PROCESS})
	if [ ${PROCSOLLCNT} -eq ${PROCISCNT} ]
	then
		echo "&green ${PROCNAME} = ${PROCISCNT} (obliged ${PROCSOLLCNT})" >> ${BBTMP}/${TEST}.$$
	elif [ ${PROCSOLLCNT} -gt ${PROCISCNT} ]
	then
		echo "&red ${PROCNAME} = ${PROCISCNT} (obliged ${PROCSOLLCNT})" >> ${BBTMP}/${TEST}.$$
	elif [ ${PROCSOLLCNT} -lt ${PROCISCNT} ]
	then
		echo "&green ${PROCNAME} = ${PROCISCNT} (obliged ${PROCSOLLCNT})" >> ${BBTMP}/${TEST}.$$
	fi
done

if ${GREP} -q "^&red" ${BBTMP}/${TEST}.$$
then
	COLOR="red"
	STATLINE="some processes are missing"
	REDLINES="$(${CAT} ${BBTMP}/${TEST}.$$)"
elif ${GREP} -q "^&yellow" ${BBTMP}/${TEST}.$$
then
	COLOR="yellow"
	STATLINE="some processes are missing"
	YELLOWLINES="$(${CAT} ${BBTMP}/${TEST}.$$)"
else
	COLOR="green"
	STATLINE="all processes ok"
	GREENLINES="$(${CAT} ${BBTMP}/${TEST}.$$)"
fi

$BB $BBDISP "status ${PREFIX}${MACHINE}.${TEST} ${COLOR} $(date) ${STATLINE}
${REDLINES}${YELLOWLINES}${GREENLINES}"

${RM} -f ${BBTMP}/${TEST}.$$
