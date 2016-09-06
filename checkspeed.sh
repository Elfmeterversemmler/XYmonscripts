#!/bin/bash

# checkspeed.sh
#
BBPROG=checkspeed.sh; export BBPROG
#
TEST="iface"
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
NOPATTERN="link|inet|lo:|bond.*:|noop|valid|virbr|team.*:"
PATTERN="Speed:|Duplex:|Link detected:"
IFCFG="/sbin/ip"
ETH="/usr/sbin/ethtool"
SD="/usr/bin/sudo"
DASHOK="Y"
DASHCOLOR="green"
CONFIG="${BBHOME}/etc/checkspeed.cfg"
ACTSEC=$(${DATE} +%s)
#
# check if a dash in interface name is ok or not
#
if ${GREP} DASHOK ${CONFIG}|${GREP} -v "^#" > /dev/null
then
	DASHOK="$(${GREP} DASHOK ${CONFIG}|${AWK} -F= '{print $2}')"
fi
if [ "${DASHOK}" = "Y" -o "${DASHOK}" = "y" ]
then
	DASHCOLOR="green"
elif [ "${DASHOK}" = "N" -o "${DASHOK}" = "n" ]
then
	DASHCOLOR="yellow"
else
	DASHCOLOR="yellow"
	echo "&${DASHCOLOR} invalid config entry ${DASHOK}. Has to be y/Y/n/N." > ${BBTMP}/${TEST}.dash
fi
#
# get the list of interfaces that are up on this machine
#
IFLIST=$(${IFCFG} addr|${EGREP} -v "${NOPATTERN}"|${AWK} -F: '{print $2}'|${AWK} -F@ '{print $1}'|${SED} 's/^ //g'|${SORT} -k1.4 -n)
#
# check if the interface has the right values compared to the config file
#
for IFACE in ${IFLIST}
do
	DOTCOLOR="red"
	if [ "$(echo ${IFACE}|${TR} -d "[a-z0-9]")" = "-" ]
	then
		echo "&${DASHCOLOR} ${IFACE} has a dash '-' in it's name" >> ${BBTMP}/${TEST}.dash
	fi
	${RM} -f ${BBTMP}/${IFACE}.$$
	${SD} ${ETH} ${IFACE}|${EGREP} "${PATTERN}"|${SED} 's/^	//g' >> ${BBTMP}/${IFACE}.$$
	REALSPEED="$(${GREP} "Speed:" ${BBTMP}/${IFACE}.$$|${AWK} '{print $2}')"
	REALDUPLEX="$(${GREP} "Duplex:" ${BBTMP}/${IFACE}.$$|${AWK} '{print $2}')"
	REALLINK="$(${GREP} "Link detected:" ${BBTMP}/${IFACE}.$$|${AWK} '{print $3}')"
	IFLINE="$(${GREP} "${IFACE}[[:space:]]" ${CONFIG})"
	if [ "$(echo ${IFLINE:0:1})" = "#" ]
	then
		${RM} -f ${BBTMP}/${IFACE}.$$
		continue
	elif [ "$(echo ${IFLINE:0:1})" = "!" ]
	then
		DOTCOLOR="blue"
	fi
	EXPSPEED="$(echo "${IFLINE}"|${AWK} '{print $2}')"
	EXPDUPLEX="$(echo "${IFLINE}"|${AWK} '{print $3}')"
	EXPLINK="$(echo "${IFLINE}"|${AWK} '{print $4}')"
	COMMENT="$(echo "${IFLINE}"|${AWK} -F\| '{print $1}'|${AWK} '{for (i=5;i<=NF;i++){printf "%s ", $i};printf("\n")}')"
	BLUE="$(echo "${IFLINE}"|${AWK} -F\| '{print $2}')"
	BLUESEC=$(${DATE} --date="${BLUE}" +%s)
	if [ ${ACTSEC} -le ${BLUESEC} ]
	then
		DOTCOLOR="blue"
		COMMENT="${COMMENT} - disabled until ${BLUE}"
	fi
	if [ "${DOTCOLOR}" = "blue" ]
	then
		echo "&${DOTCOLOR} ${IFACE} ${REALSPEED} ${REALDUPLEX} - Link ${REALLINK}	${COMMENT}" >> ${BBTMP}/${TEST}
	elif [[ "${REALDUPLEX}" = "${EXPDUPLEX}" && "${REALSPEED}" = "${EXPSPEED}" && "${REALLINK}" = "${EXPLINK}" ]]
	then
		echo "&green ${IFACE} ${REALSPEED} ${REALDUPLEX} - Link ${REALLINK}	${COMMENT}" >> ${BBTMP}/${TEST}
	else
		echo "&${DOTCOLOR} ${IFACE} ${REALSPEED} ${REALDUPLEX} - Link ${REALLINK}	${COMMENT}" >> ${BBTMP}/${TEST}
	fi
	${RM} -f ${BBTMP}/${IFACE}.$$
done

echo >> ${BBTMP}/${TEST}
echo >> ${BBTMP}/${TEST}
${CAT} ${BBTMP}/${TEST}.dash >> ${BBTMP}/${TEST} 2>/dev/null
#
# determine the color of the whole test
#
if ${GREP} -q "^&red" ${BBTMP}/${TEST}
then
	COLOR="red"
	STATLINE="possible interface problems"
	REDLINES="$(${CAT} ${BBTMP}/${TEST})"
elif ${GREP} -q "^&yellow" ${BBTMP}/${TEST}
then
	COLOR="yellow"
	STATLINE="possible interface problems"
	YELLOWLINES="$(${CAT} ${BBTMP}/${TEST})"
else
	COLOR="green"
	STATLINE="no interface problems"
	GREENLINES="$(${CAT} ${BBTMP}/${TEST})"
fi
#
# release the data
#
$BB $BBDISP "status ${MACHINE}.${TEST} ${COLOR} $(date) ${STATLINE}
${REDLINES}${YELLOWLINES}${GREENLINES}"
#
# clean up
#
${RM} -f ${BBTMP}/${TEST}
${RM} -f ${BBTMP}/${TEST}.dash
${RM} -f ${BBTMP}/${IFACE}.$$
