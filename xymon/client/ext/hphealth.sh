#!/bin/sh
#
# hphealth.sh
#
BBPROG=hphealth.sh; export BBPROG
#
TEST="hphealth"
#
# BBHOME=/home/sean/bb; export BBHOME	# FOR TESTING

if test "$BBHOME" = ""
then
	if [ -d ${HOME}/hobbit/client ]
	then
		BBHOME="${HOME}/hobbit/client"
	elif [ -d ${HOME}/bb ]
	then
		BBHOME="${HOME}/bb"
	else
		echo "can not set BBHOME... exiting"
		exit 1
	fi
fi
CONFIG="${BBHOME}/etc/${TEST}.cfg"
CMDLINE="${1}"

if [ "${CMDLINE}" = "-ignore" ]
then
	printf "Which part should be ignored (e.g.: '1:1E:1:2'/'module 1:3') : "
	read MODULE
	printf "How long should it be ignored (e.g.: 3 weeks/1 month/10 days) : "
	read ITIME
	printf "What's the reason (e.g.: call opened/dimm ordered) : "
	read REASON
	echo "${MODULE} | ${ITIME} | ${REASON}" >> ${CONFIG}
	exit 0
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
MXTMPPRC="4/5"				# max. temperature percentage, default = 80%
MINBAD="80"				# max. bad blocks on SSD, default = 20%
GREENERR1="controller does not have any physical drives on it"
GREENERR2="specified device does not have any logical drives"
GREENERR3="The controller identified by.*was not detected"
SD="/usr/bin/sudo"
FIOSTAT="/usr/bin/fio-status"
FIOPCHK="/usr/bin/fio-pci-check"
OUTFILE="${BBTMP}/${TEST}"
LSM="/sbin/lsmod"
MODULE="iomemory_vsl"
SSDCHECK="n"
ACTSEC=$(${DATE} +%s)

${RM} -f ${OUTFILE}_asm.$$
${RM} -f ${OUTFILE}_asm
${RM} -f ${OUTFILE}_fios.$$
${RM} -f ${OUTFILE}_fiop.$$
${RM} -f ${OUTFILE}.$$
${RM} -f ${OUTFILE}

if ${LSM}|${GREP} ${MODULE} >/dev/null
then
	MODSTAT="y"
else
	MODSTAT="n"
fi

if ${GREP} ^SSDCHECK ${CONFIG} > /dev/null
then
	SSDCHECK="$(${GREP} ^SSDCHECK ${CONFIG}|${AWK} -F= '{print $2}'|${TR} -d '"')"
fi

if [ ! -s "${BBTMP}/HPASMCLI" ]
then
	echo "&yellow no output from hpasmcli found" >> ${OUTFILE}_asm
else
	if [[ "$(${HEAD} -n 1 ${BBTMP}/HPASMCLI)" =~ "CRITICAL.*needs to be restarted" ]]
	then
		echo "&red hpasmd needs to be restarted" >> ${OUTFILE}_asm
	else
		SYSNAME="$(${HEAD} -n 1 ${BBTMP}/HPASMCLI|${AWK} -F\' '{print $2}')"
		SYSNUMB="$(${HEAD} -n 1 ${BBTMP}/HPASMCLI|${AWK} -F\' '{print $4}')"
		SYSROM="$(${HEAD} -n 1 ${BBTMP}/HPASMCLI|${AWK} -F\' '{print $6}')"
		SYSINFO="System type : ${SYSNAME}<br>Serial no.  : ${SYSNUMB}<br>System ROM  : ${SYSROM}"

		${TAIL} -n +2 < ${BBTMP}/HPASMCLI|${SED} '/^checking/s/$/<\/b><\/u><br>/g;s/^checking /<br><br><u><b>/g' > ${OUTFILE}_asm
	fi
fi

${CAT} ${OUTFILE}_asm|while read PART REST
do
	if [ "${PART}" = "cpu" -o "${PART}" = "powersupply" ]
	then
		STAT="$(echo "${REST}"|${AWK} '{print $(NF-1),$NF}')"
		if [ "${STAT}" != "is ok" ]
		then
			ICON="yellow"
		else
			ICON="green"
		fi
		echo "&${ICON} ${PART} ${REST}" >> ${OUTFILE}
	elif [ "${PART}" = "dimm" ]
	then
		COMMENT=""
		STAT="$(echo "${REST}"|${AWK} '{print $(NF-1),$NF}')"
		MODULE="$(echo "${REST}"|${AWK} '{print $1,$2}')"
		if [ "${STAT}" != "is ok" ]
		then
			ICON="red"
			if ${GREP} "^${MODULE}" ${CONFIG} >/dev/null 2>&1
			then
				BLU="$(${GREP} -w ^"${MODULE}" ${CONFIG}|${AWK} -F\| '{print $2}'|${SED} 's/ //g')"
				COMMENT="	# $(${GREP} -w "^${MODULE}" ${CONFIG}|${AWK} -F\| '{print $3}') - disabled for/until ${BLU}"
				if [ "${BLU}" = "" ]
				then
					BLUSEC="0"
					COMMENT="	# incorrect config file entry - ignored"
				elif [ "${BLU}" = "forever" ]
				then
					BLUSEC="2147483647"
				else
					BLUSEC=$(${DATE} --date="${BLU}" +%s)
				fi
				if [ ${ACTSEC} -le ${BLUSEC} ]
				then
					if [ "${ICON}" = "green" ]
					then
						${SED} -i "/^${MODULE}/d" ${CONFIG}
						COMMENT=""
					else
						ICON="clear"
					fi
				else
					${SED} -i "/^${MODULE}/d" ${CONFIG}
					COMMENT=""
				fi
			fi
		else
			ICON="green"
		fi
		echo "&${ICON} ${PART} ${REST}	${COMMENT}" >> ${OUTFILE}
	elif [ "${PART}" = "fan" ]
	then
		if echo "${REST}"|${GREP} -q "speed is normal"
		then
			ICON="green"
		else
			ICON="yellow"
		fi
		echo "&${ICON} ${PART} ${REST}" >> ${OUTFILE}
	elif [ ${PART} -eq ${PART} 2>/dev/null ]
	then
		ACTTEMP="$(echo ${REST}|${AWK} '{print $4}'|${TR} -d "[:alpha:]")"
		MAXTEMP="$(echo ${REST}|${AWK} '{print $5}'|${TR} -d "(")"
		WARTEMP=$((${MAXTEMP}*${MXTMPPRC}))
		if [ ${ACTTEMP} -ge ${WARTEMP} ]
		then
			ICON="yellow"
		else
			ICON="green"
		fi
		echo "&${ICON} ${PART} ${REST}" >> ${OUTFILE}
	else
		echo "${PART} ${REST}" >> ${OUTFILE}
	fi
done

${CAT} ${BBTMP}/HPACUCLI1 ${BBTMP}/HPACUCLI2 > ${BBTMP}/HPACUCLI 2>/dev/null

if [ ! -s "${BBTMP}/HPACUCLI" ]
then
	echo "&yellow no output from hpacucli found" >> ${OUTFILE}
else
	${CAT} ${BBTMP}/HPACUCLI|while read PART REST
	do
		COMMENT=""
		if [ "${PART}" = "logicaldrive" ]
		then
			STAT="$(echo "${REST}"|${AWK} -F: '{print $2}'|${SED} 's/ //g'|${AWK} -F, '{print $1}')"
			if [ "${STAT}" != "OK" -a "${STAT}" != "Recovering" ]
			then
				ICON="yellow"
			else
				ICON="green"
			fi
			echo "&${ICON} ${PART} ${REST}" >> ${OUTFILE}
		elif [ "${PART}" = "physicaldrive" ]
		then
			STAT="$(echo "${REST}"|${AWK} '{print $NF}')"
			DISK="$(echo "${REST}"|${AWK} '{print $1}')"
			case "${STAT}" in
			OK)
				ICON="green";;
			Rebuilding)
				ICON="clear";;
			Failure|Failed)
				ICON="red";;
			*)
				ICON="yellow";;
			esac
			if ${GREP} -w ^${DISK} ${CONFIG} >/dev/null 2>&1
			then
				BLU="$(${GREP} -w ^"${DISK}" ${CONFIG}|${AWK} -F\| '{print $2}'|${SED} 's/ //g')"
				COMMENT="	# $(${GREP} -w ^${DISK} ${CONFIG}|${AWK} -F\| '{print $3}') - disabled for/until ${BLU}"
				if [ "${BLU}" = "" ]
				then
					BLUSEC="0"
					COMMENT="	# incorrect config file entry - ignored"
				elif [ "${BLU}" = "forever" ]
				then
					BLUSEC="2147483647"
				else
					BLUSEC=$(${DATE} --date="${BLU}" +%s)
				fi
				if [ ${ACTSEC} -le ${BLUSEC} ]
				then
					if [ "${ICON}" = "green" ]
					then
						${SED} -i "/^${DISK}/d" ${CONFIG}
						COMMENT=""
					else
						ICON="clear"
					fi
				else
					${SED} -i "/^${DISK}/d" ${CONFIG}
					COMMENT=""
				fi
			fi
			echo "&${ICON} ${PART} ${REST}  ${COMMENT}" >> ${OUTFILE}
		elif [ "${PART}" = "Error:" ]
		then
			if echo "${REST}"|${GREP} -q "${GREENERR1}"
			then
				echo "&clear no physical drives installed" >> ${OUTFILE}
			elif echo "${REST}"|${GREP} -q "${GREENERR2}"
			then
				echo "&clear no logical drives installed" >> ${OUTFILE}
			elif echo "${REST}"|${GREP} -q "${GREENERR3}"
			then
				echo "&clear no controller installed" >> ${OUTFILE}
			else
				echo "&yellow unknown error : ${REST}" >> ${OUTFILE}
			fi
		else
			echo "${PART} ${REST}" >> ${OUTFILE}
		fi
	done
fi

if [ -e "${FIOSTAT}" -a -e "${FIOPCHK}" -a "${MODSTAT}" = "y" -a "${SSDCHECK}" = "y" ]
then
	echo "<br><br><u><b>ssd</b></u><br>" >> ${OUTFILE}
	${SD} ${FIOSTAT} -fk > ${OUTFILE}_fios.$$
	${SD} ${FIOPCHK} > ${OUTFILE}_fiop.$$
	MEDSTAT="$(${GREP} "media_status" ${OUTFILE}_fios.$$|${AWK} -F= '{print $2}')"
	GOODBLK="$(${GREP} "blocks_good_percent" ${OUTFILE}_fios.$$|${AWK} -F= '{print $2}'|${CUT} -d. -f1)"
	NDSPEED="$(${GREP} "Needed" ${OUTFILE}_fiop.$$|${AWK} '{print $2,$3}')"
	ISSPEED="$(${GREP} "Needed" ${OUTFILE}_fiop.$$|${AWK} '{print $5,$6}')"
	if [ "${MEDSTAT}" = "Healthy" ]
	then
		ICON="green"
	else
		ICON="yellow"
	fi
	echo "&${ICON} media status = ${MEDSTAT}" >> ${OUTFILE}
	if [ ${GOODBLK} -lt ${MINBAD} ]
	then
		ICON="yellow"
	else
		ICON="green"
	fi
	echo "&${ICON} good blocks on SSD ${GOODBLK}%" >> ${OUTFILE}
	if [ "${ISSPEED}" = "${NDSPEED}" ]
	then
		ICON="green"
		echo "&${ICON} available speed (${ISSPEED}) matches needed speed (${NDSPEED})" >> ${OUTFILE}
	else
		ICON="yellow"
		echo "&${ICON} available speed (${ISSPEED}) does not match needed speed (${NDSPEED})" >> ${OUTFILE}
	fi
fi

COLLIST="$(${GREP} "^\&" ${OUTFILE}|${AWK} '{print $1}'|${SED} 's/^&//g'|${SORT} -u)"
if echo ${COLLIST}|${GREP} -q "red"
then
	COLOR="red"
elif echo ${COLLIST}|${GREP} -q "yellow"
then
	COLOR="yellow"
fi

$BB $BBDISP "status ${MACHINE}.${TEST} ${COLOR} `date` ${STATLINE}
${SYSINFO}<br>
$(${CAT} ${OUTFILE})"

${RM} -f ${OUTFILE}_asm.$$
${RM} -f ${OUTFILE}_asm
${RM} -f ${OUTFILE}_fios.$$
${RM} -f ${OUTFILE}_fiop.$$
${RM} -f ${OUTFILE}.$$
${RM} -f ${OUTFILE}
