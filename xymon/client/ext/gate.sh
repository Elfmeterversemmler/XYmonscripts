#!/usr/bin/bash

# gate
#
BBPROG=gate; export BBPROG
#
TEST="gate"

if test "$BBHOME" = ""
then
	echo "BBHOME is not set... exiting"
	exit 1
fi

if test ! "$BBTMP"
then
	. $BBHOME/etc/bbdef.sh
fi

COLOR="green"   # Let's assume all is ok
STATLINE=""
GREENLINES=""
REDLINES=""
AWK="/usr/xpg4/bin/awk"
EGREP="/usr/xpg4/bin/egrep"
GREP="/usr/xpg4/bin/grep"
BBETC="${BBHOME}/etc"
CFGFILE="${BBETC}/gate.cfg"
MMG="./mmg"
HOLICHECK="${BBHOME}/ext/holicheck"

${HOLICHECK} ${BBETC}/holiday_all.dat
ISXCHNGHOL="${?}"

export LD_LIBRARY_PATH=../lib
export SYS_CONFIG_FILE=../cfg/configsys.ini

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
#
# Set variables for all config from config file
#
for CFG in $(get_config_list <(${SED} 's/#.*$//g' ${CFGFILE}))
do
	${RM} -f ${BBTMP}/${CFG}.$$
	${RM} -f ${BBTMP}/xervice.${CFG}
	${RM} -f ${BBTMP}/XERVICE.${CFG}
	${RM} -f ${BBTMP}/${CFG}.broad.$$
	${RM} -f ${BBTMP}/${CFG}.broad
	unset $(set | ${AWK} -F= '/^gate_/  { print $1 }') gate_
	set_config_vars <(${SED} 's/#.*$//g' ${CFGFILE}) ${CFG} gate_
	GLOBSTART=$((10#$(echo ${gate_BASETIME}|${AWK} -F\- '{print $1}')))
	GLOBSTOPP=$((10#$(echo ${gate_BASETIME}|${AWK} -F\- '{print $2}')))
	TIME=$((10#$(${DATE} +%H%M)))
	WDAY=$(${DATE} +%w)
	MAXCOLOR="red"
	MULTICOUNT=10
	MULTICAST=0
	LOIX="NULL"
	PREFIX=""
	if [ -n "${gate_PREFIX}" ]
	then
		PREFIX="${gate_PREFIX}"
	fi
	if [[ ${TIME} -le ${GLOBSTART} || ${TIME} -gt ${GLOBSTOPP} || ${WDAY} -eq 0 || ${WDAY} -eq 6 ]]
	then
		echo "&green Outside monitoring hours (${gate_BASETIME} or weekend)" > ${BBTMP}/${CFG}.$$
	elif [[ "${gate_BASEDIR}" =~ "base90" && ${ISXCHNGHOL} -eq 0 ]]
	then
		echo "&green Exchange holiday" > ${BBTMP}/${CFG}.$$
	else
		if [[ -f "${gate_BASEDIR}/logs/exceptions/active/elb.local.log" && -w "${gate_BASEDIR}/logs/exceptions/active/elb.local.log" ]]
		then
			cd ${gate_BASEDIR}/bin
			if ! ${MMG} GWS show status|${GREP} -q '@"bb"'
			then
				${MMG} GWS context create bb
			fi
			if [ -n "${gate_MAXCOLOR}" ]
			then
				MAXCOLOR="${gate_MAXCOLOR}"
			fi
			if [ -n "${gate_MULTICAST}" ]
			then
				MULTICAST="${gate_MULTICAST}"
			fi
			if [ -n "${gate_MULTICOUNT}" ]
			then
				MULTICOUNT="${gate_MULTICOUNT}"
			fi
			if [ -n "${gate_IGNXERV}" ]
			then
				LOIX="${gate_IGNXERV}"
			fi
			IGNXERV="$(echo ${LOIX}|${SED} 's/,/\ /g')"
			THISCLIENT=$(${MMG} GWS show ThisClient|${GREP} "+.*+")
			MISSNAME=$(echo "${THISCLIENT}"|${AWK} '{print $1}')
			MISSID=$(echo "${THISCLIENT}"|${AWK} '{print $2}')
			${MMG} GWS show bb BroadcastCounter ThisClient|${GREP} "^${MISSNAME}" >> ${BBTMP}/${CFG}.broad.$$
			printf "MISS   : ${MISSNAME}\nMISS-ID: ${MISSID}\n<hr>\n<h2 align=center>XSERVICES</h2><br>\n" > ${BBTMP}/${CFG}.$$
			printf "   %-25s STATE\n" XERVICE >> ${BBTMP}/${CFG}.$$
			${MMG} GWC show XerviceRouting > ${BBTMP}/xervice.${CFG}
			INXVC=""
			IXVC=""
			for IGNXVC in ${IGNXERV}
			do
				XVC=$(echo ${IGNXVC}|${AWK} -F\: '{print $1}')
				TIMEFRAME=$(echo ${IGNXVC}|${AWK} -F\: '{print $2}')
				if [ "${TIMEFRAME}" = "" ]
				then
					INXVC="${XVC} ${INXVC}"
				elif [ "${TIMEFRAME}" != "" ]
				then
					IGNSTART=$((10#$(echo ${TIMEFRAME}|${AWK} -F\- '{print $1}')))
					IGNSTOPP=$((10#$(echo ${TIMEFRAME}|${AWK} -F\- '{print $2}')))
					if [[ ${TIME} -ge ${IGNSTART} && ${TIME} -lt ${IGNSTOPP} ]]
					then
						INXVC="${INXVC} ${XVC}"
					fi
				fi
			done
			for HOLXVC in FFM VIE ISE
			do
				if ${HOLICHECK} ${BBETC}/holiday_${HOLXVC}.dat
				then
					if [ "${HOLXVC}" = "FFM" ]
					then
						HOLXVC="${HOLXVC} FF2"
					fi
					INXVC="${INXVC} ${HOLXVC}"
				fi
			done
			IXVC=$(echo ${INXVC}|${SED} 's/\ /|/g')
			${MMG} XERVICE|while read LINE
			do
				if [[ "${LINE}" =~ "Cannot connect to process: AVAILABILITY_MANAGER" ]]
				then
					echo "&red Basic Architecture is down, no AVAILABILITY_MANAGER" >> ${BBTMP}/${CFG}.$$
					break
				else
					XRVC=$(echo ${LINE}|${AWK} '{print $1}')
					STATE=$(echo ${LINE}|${AWK} '{print $2}')
					if [ "${STATE}" = "AVAILABLE" ]
					then
						printf "&green %-25s AVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
					elif [ "${STATE}" = "UNAVAILABLE" ]
					then
						if ${GREP} -wq "${XRVC}" ${BBTMP}/xervice.${CFG}
						then
							printf "&yellow %-25s REMOTE AVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
						else
							if echo ${XRVC}|${EGREP} -q ${IXVC}
							then
								printf "&blue %-25s UNAVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
							else
								printf "&${MAXCOLOR} %-25s UNAVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
							fi
						fi
					fi
				fi
			done
			case ${MULTICAST} in
			1)
				${CAT} ${BBTMP}/${CFG}.broad.$$|while read LINE
				do
					echo "&green ${LINE}" >> ${BBTMP}/${CFG}.broad
				done
				;;
			2)
				${CAT} ${BBTMP}/${CFG}.broad.$$|while read LINE
				do
					if [[ "$(echo "${LINE}"|${AWK} '{print $9}')" = "nr" || ${gate_MULTICOUNT} -gt $(echo "${LINE}"|${AWK} '{print $9}') ]]
					then
						echo "&green ${LINE}" >> ${BBTMP}/${CFG}.broad
					else
						echo "&yellow ${LINE}" >> ${BBTMP}/${CFG}.broad
					fi
				done
				;;
			3)
				${CAT} ${BBTMP}/${CFG}.broad.$$|while read LINE
				do
					if [[ "$(echo "${LINE}"|${AWK} '{print $9}')" = "nr" || ${gate_MULTICOUNT} -gt $(echo "${LINE}"|${AWK} '{print $9}') ]]
					then
						echo "&green ${LINE}" >> ${BBTMP}/${CFG}.broad
					else
						echo "&${MAXCOLOR} ${LINE}" >> ${BBTMP}/${CFG}.broad
					fi
				done
				;;
			esac
			if [ ${MULTICAST} -eq 0 ]
			then
				${RM} -f ${BBTMP}/${CFG}.broad
			else
				printf "\n<hr>\n<h2 align=center>Multicast</h2>\n\n" >> ${BBTMP}/${CFG}.$$
				printf "    Name       Id  Address          Xervice                   Stream FilterIndex       total rerequested      lost   last reset\n" >> ${BBTMP}/${CFG}.$$
				${CAT} ${BBTMP}/${CFG}.broad >> ${BBTMP}/${CFG}.$$
			fi
		elif [[ -f "${gate_BASEDIR}/logs/exceptions/active/elb.local.log" && ! -w "${gate_BASEDIR}/logs/exceptions/active/elb.local.log" ]]
		then
			echo "&yellow elb.local.log is not writable<br><br>" >> ${BBTMP}/${CFG}.$$
			cd ${gate_BASEDIR}/bin
			if ! ${MMG} GWS show status|${GREP} -q '@"bb"'
			then
				${MMG} GWS context create bb
			fi
			if [ -n "${gate_MAXCOLOR}" ]
			then
				MAXCOLOR="${gate_MAXCOLOR}"
			fi
			if [ -n "${gate_MULTICAST}" ]
			then
				MULTICAST="${gate_MULTICAST}"
			fi
			if [ -n "${gate_MULTICOUNT}" ]
			then
				MULTICOUNT="${gate_MULTICOUNT}"
			fi
			if [ -n "${gate_IGNXERV}" ]
			then
				LOIX="${gate_IGNXERV}"
			fi
			IGNXERV="$(echo ${LOIX}|${SED} 's/,/\ /g')"
			THISCLIENT=$(${MMG} GWS show ThisClient|${GREP} "+.*+")
			MISSNAME=$(echo "${THISCLIENT}"|${AWK} '{print $1}')
			MISSID=$(echo "${THISCLIENT}"|${AWK} '{print $2}')
			${MMG} GWS show bb BroadcastCounter ThisClient|${GREP} "^${MISSNAME}" >> ${BBTMP}/${CFG}.broad.$$
			printf "MISS   : ${MISSNAME}\nMISS-ID: ${MISSID}\n<hr>\n<h2 align=center>XSERVICES</h2><br>\n" > ${BBTMP}/${CFG}.$$
			printf "   %-25s STATE\n" XERVICE >> ${BBTMP}/${CFG}.$$
			${MMG} GWC show XerviceRouting > ${BBTMP}/xervice.${CFG}
			INXVC=""
			IXVC=""
			for IGNXVC in ${IGNXERV}
			do
				XVC=$(echo ${IGNXVC}|${AWK} -F\: '{print $1}')
				TIMEFRAME=$(echo ${IGNXVC}|${AWK} -F\: '{print $2}')
				if [ "${TIMEFRAME}" = "" ]
				then
					INXVC="${XVC} ${INXVC}"
				elif [ "${TIMEFRAME}" != "" ]
				then
					IGNSTART=$((10#$(echo ${TIMEFRAME}|${AWK} -F\- '{print $1}')))
					IGNSTOPP=$((10#$(echo ${TIMEFRAME}|${AWK} -F\- '{print $2}')))
					if [[ ${TIME} -ge ${IGNSTART} && ${TIME} -lt ${IGNSTOPP} ]]
					then
						INXVC="${INXVC} ${XVC}"
					fi
				fi
			done
			for HOLXVC in FFM VIE ISE
			do
				if ${HOLICHECK} ${BBETC}/holiday_${HOLXVC}.dat
				then
					if [ "${HOLXVC}" = "FFM" ]
					then
						HOLXVC="${HOLXVC} FF2"
					fi
					INXVC="${INXVC} ${HOLXVC}"
				fi
			done
			IXVC=$(echo ${INXVC}|${SED} 's/\ /|/g')
			${MMG} XERVICE|while read LINE
			do
				if [[ "${LINE}" =~ "Cannot connect to process: AVAILABILITY_MANAGER" ]]
				then
					echo "&red Basic Architecture is down, no AVAILABILITY_MANAGER" >> ${BBTMP}/${CFG}.$$
					break
				else
					XRVC=$(echo ${LINE}|${AWK} '{print $1}')
					STATE=$(echo ${LINE}|${AWK} '{print $2}')
					if [ "${STATE}" = "AVAILABLE" ]
					then
						printf "&green %-25s AVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
					elif [ "${STATE}" = "UNAVAILABLE" ]
					then
						if echo ${XRVC}|${EGREP} -q ${IXVC}
						then
							printf "&blue %-25s UNAVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
						else
							if ${GREP} -wq "${XRVC}" ${BBTMP}/xervice.${CFG}
							then
								printf "&yellow %-25s REMOTE AVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
							else
								printf "&${MAXCOLOR} %-25s UNAVAILABLE\n" ${XRVC} >> ${BBTMP}/${CFG}.$$
							fi
						fi
					fi
				fi
			done
			case ${MULTICAST} in
			1)
				${CAT} ${BBTMP}/${CFG}.broad.$$|while read LINE
				do
					echo "&green ${LINE}" >> ${BBTMP}/${CFG}.broad
				done
				;;
			2)
				${CAT} ${BBTMP}/${CFG}.broad.$$|while read LINE
				do
					if [[ "$(echo "${LINE}"|${AWK} '{print $9}')" = "nr" || ${gate_MULTICOUNT} -gt $(echo "${LINE}"|${AWK} '{print $9}') ]]
					then
						echo "&green ${LINE}" >> ${BBTMP}/${CFG}.broad
					else
						echo "&yellow ${LINE}" >> ${BBTMP}/${CFG}.broad
					fi
				done
				;;
			3)
				${CAT} ${BBTMP}/${CFG}.broad.$$|while read LINE
				do
					if [[ "$(echo "${LINE}"|${AWK} '{print $9}')" = "nr" || ${gate_MULTICOUNT} -gt $(echo "${LINE}"|${AWK} '{print $9}') ]]
					then
						echo "&green ${LINE}" >> ${BBTMP}/${CFG}.broad
					else
						echo "&${MAXCOLOR} ${LINE}" >> ${BBTMP}/${CFG}.broad
					fi
				done
				;;
			esac
			if [ ${MULTICAST} -eq 0 ]
			then
				${RM} -f ${BBTMP}/${CFG}.broad
			else
				printf "\n<hr>\n<h2 align=center>Multicast</h2>\n\n" >> ${BBTMP}/${CFG}.$$
				printf "    Name       Id  Address          Xervice                   Stream FilterIndex       total rerequested      lost   last reset\n" >> ${BBTMP}/${CFG}.$$
				${CAT} ${BBTMP}/${CFG}.broad >> ${BBTMP}/${CFG}.$$
			fi
		else
			echo "&red Basic Architecture is down, elb.local.log is missing" >> ${BBTMP}/${CFG}.$$
		fi
	fi
	if ${EGREP} -q "^&red" ${BBTMP}/${CFG}.$$
	then
		COLOR="red"
		STATLINE="possible MISS problems"
	elif ${EGREP} -q "^&yellow" ${BBTMP}/${CFG}.$$
	then
		COLOR="yellow"
		STATLINE="possible MISS problems"
	else
		COLOR="green"
		STATLINE="no MISS problems"
	fi

	${BB} ${BBDISP} "status ${PREFIX}${MACHINE}.${CFG} ${COLOR} $(${DATE}) ${STATLINE}
$(${CAT} ${BBTMP}/${CFG}.$$)"
	${RM} -f ${BBTMP}/${CFG}.$$
	${RM} -f ${BBTMP}/xervice.${CFG}
	${RM} -f ${BBTMP}/XERVICE.${CFG}
	${RM} -f ${BBTMP}/${CFG}.broad.$$
	${RM} -f ${BBTMP}/${CFG}.broad
done
