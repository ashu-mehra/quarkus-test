#!/bin/bash

shopt -s extglob

logfile=out

DEFAULT_QUARKUS_APP_JAR="target/getting-started-1.0-SNAPSHOT-runner.jar"
DEFAULT_QUARKUS_APP_NATIVE="target/getting-started-1.0-SNAPSHOT-runner"

datediff() {
	local start=$1
	local end=$2

	sec_start=$(date -d "$start" +%s)
	sec_start=${sec_start##+(0)}	# remove leading zeros
	sec_end=$(date -d "$end" +%s)
	sec_end=${sec_end##+(0)}
	secdiff=$(($sec_end - $sec_start))
	#echo "secdiff: ${secdiff}"

	nsec_start=$(date -d "$start" +%N)
	nsec_start=${nsec_start##+(0)}
	nsec_end=$(date -d "$end" +%N)
	nsec_end=${nsec_end##+(0)}
	nsecdiff=$(($nsec_end - $nsec_start))
	#echo "nanosecdiff: ${nsecdiff}"

	#printf "sec: %s nanosec: %s\n" $secdiff $nsecdiff
	final=$((($secdiff * 1000) + ($nsecdiff / 1000000)))
	echo "$final"
}

check_env() {
	local cdir=`pwd`

	if [ -z "${JAVA_HOME}" ];
	then
		echo "JAVA_HOME is not set"
		exit 1
	fi
	if [ -z "${CRIU_HOME}" ];
	then
		echo "CRIU_HOME is not set"
		exit 1
	fi
	if [ -z "${QUARKUS_APP_JAR}" ];
	then
		echo "QUARKUS_APP_JAR is not set"
		if [ -f ${DEFAULT_QUARKUS_APP_JAR} ]; then
			echo "Setting QUARKUS_APP_JAR to ${cdir}/${DEFAULT_QUARKUS_APP_JAR}"
			QUARKUS_APP_JAR=${cdir}/${DEFAULT_QUARKUS_APP_JAR}
		else
			exit 1
		fi
	fi
	if [ -z "${QUARKUS_APP_NATIVE}" ];
	then
		echo "QUARKUS_APP_NATIVE is not set"
		if [ -f ${DEFAULT_QUARKUS_APP_NATIVE} ]; then
			echo "Setting QUARKUS_APP_NATIVE to ${cdir}/${DEFAULT_QUARKUS_APP_NATIVE}"
			QUARKUS_APP_NATIVE=${cdir}/${DEFAULT_QUARKUS_APP_NATIVE}
		else
			exit 1
		fi
	fi
}

get_restore_time() {
	restore_time=`${CRIU_HOME}/crit/crit show stats-restore | grep restore_time | cut -d ':' -f 2 | cut -d ',' -f 1`
	echo "time to restore: " $((${restore_time}/1000))
}

pre() {
	check_env

	rm -fr native criu openj9 openj9_scc
	mkdir -p native criu openj9 openj9_scc

	echo -n "Removing scc..."
	${JAVA_HOME}/bin/java -Xshareclasses:name=quarkus,destroyAll &> /dev/null
	echo "Done"

	echo -n "Creating scc..."
	${JAVA_HOME}/bin/java -Xshareclasses:name=quarkus -jar ${QUARKUS_APP_JAR} &> /dev/null &
	sleep 5s
	./hit_url.sh
	echo "Done"
	sleep 1s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null
}

test_native() {
	logdir="native"

	./hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	${QUARKUS_APP_NATIVE} &> ${logdir}/${logfile}.${itr} &
	sleep 2s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "native pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logdir}/${logfile}.${itr} | head -n 1 | cut -d '=' -f 2`
	echo "Start: ${start} End: ${end}"

	#datediff "09:25:46.982" "09:25:47.009" #${start} ${end}
	printf "native: %s\n" $(datediff ${start} ${end})
	native_values+=($(datediff ${start} ${end}))
}

test_criu_appstart() {
	logdir="criu"
	cdir=`pwd`

	rm -fr checkpoint
	mkdir checkpoint
	pushd checkpoint &>/dev/null

	setsid ${JAVA_HOME}/bin/java -jar ${QUARKUS_APP_JAR} </dev/null &>${logfile}.${itr} &
	sleep 5s
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid to dump: ${pid}"
	${CRIU_HOME}/scripts/criu-ns dump -t ${pid} --tcp-established -v3 -o dump.log

	sleep 1s

	${cdir}/hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	#echo "start: ${start}"
	${CRIU_HOME}/scripts/criu-ns restore -d --tcp-established -v3 -o restore.log
	sleep 5s

	get_restore_time
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logfile}.${itr} | head -n 1 | cut -d '=' -f 2`
	cp ${logfile}.${itr} ${cdir}/${logdir}
	echo "Start: ${start} End: ${end}"

	printf "criu: %s\n" $(datediff ${start} ${end})

	popd &>/dev/null
	criu_appstart_values+=($(datediff ${start} ${end}))
}

test_criu_response() {
	logdir="criu"
	cdir=`pwd`

	rm -fr checkpoint
	mkdir checkpoint
	pushd checkpoint &>/dev/null

	setsid ${JAVA_HOME}/bin/java -jar ${QUARKUS_APP_JAR} </dev/null &>${logfile}.${itr} &
	sleep 5s
	${cdir}/hit_url.sh
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid to dump: ${pid}"
	${CRIU_HOME}/scripts/criu-ns dump -t ${pid} --tcp-established -v3 -o dump.log

	sleep 1s

	${cdir}/hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	#echo "start: ${start}"
	${CRIU_HOME}/scripts/criu-ns restore -d --tcp-established -v3 -o restore.log
	sleep 5s

	get_restore_time
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logfile}.${itr} | head -n 2 | tail -n 1 | cut -d '=' -f 2`
	cp ${logfile}.${itr} ${cdir}/${logdir}
	echo "Start: ${start} End: ${end}"

	printf "criu: %s\n" $(datediff ${start} ${end})

	popd &>/dev/null
	criu_response_values+=($(datediff ${start} ${end}))
}

test_criu_scc() {
	logdir="criu"
	cdir=`pwd`

	rm -fr checkpoint
	mkdir checkpoint
	pushd checkpoint &>/dev/null

	setsid ${JAVA_HOME}/bin/java -Xshareclasses:name=quarkus,readonly -jar ${QUARKUS_APP_JAR} </dev/null &>${logfile}.${itr} &
	sleep 5s
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid to dump: ${pid}"
	${CRIU_HOME}/scripts/criu-ns dump -t ${pid} --tcp-established -v3 -o dump.log

	sleep 1s

	${cdir}/hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	#echo "start: ${start}"
	${CRIU_HOME}/scripts/criu-ns restore -d --tcp-established -v3 -o restore.log
	sleep 5s

	get_restore_time
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logfile}.${itr} | head -n 2 | tail -n 1 | cut -d '=' -f 2`
	cp ${logfile}.${itr} ${cdir}/${logdir}
	echo "Start: ${start} End: ${end}"

	printf "criu: %s\n" $(datediff ${start} ${end})

	popd &>/dev/null
	criu_scc_values+=($(datediff ${start} ${end}))
}

test_openj9() {
	logdir="openj9"

	./hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	${JAVA_HOME}/bin/java -jar ${QUARKUS_APP_JAR} &> ${logdir}/${logfile}.${itr} &
	sleep 5s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logdir}/${logfile}.${itr} | head -n 1 | cut -d '=' -f 2`
	echo "Start: ${start} End: ${end}"

	#datediff "09:25:46.982" "09:25:47.009" #${start} ${end}
	printf "openj9: %s\n" $(datediff ${start} ${end})
	openj9_values+=($(datediff ${start} ${end}))
}

test_openj9_scc() {
	logdir="openj9_scc"

	./hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	${JAVA_HOME}/bin/java -Xshareclasses:name=quarkus,readonly -jar ${QUARKUS_APP_JAR} &> ${logdir}/${logfile}.${itr} &
	sleep 5s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logdir}/${logfile}.${itr} | head -n 1 | cut -d '=' -f 2`
	echo "Start: ${start} End: ${end}"

	#datediff "09:25:46.982" "09:25:47.009" #${start} ${end}
	printf "openj9_scc: %s\n" $(datediff ${start} ${end})
	openj9_scc_values+=($(datediff ${start} ${end}))
}

get_average() {
	arr=("$@")
	#echo "values: ${arr[@]}"
	for val in ${arr[@]}
	do
		sum=$(( $sum + $val ))
	done
	#echo "sum: $sum"
	#echo "count: ${#arr[@]}"
	echo $(( $sum / ${#arr[@]} ))	
}

get_averages() {
	for key in ${headers[@]}
	do
		if [ ${flags[$key]} -eq 1 ]; then
			value_list=(${values[$key]})
			#echo "value_list: ${value_list[@]}"
			#get_average ${value_list[@]}
			averages[$key]=$(get_average ${value_list[@]})
		fi
	done
}

print_summary() {
	echo "########## Summary ##########"
	printf "\t"
	for key in ${headers[@]}
	do
		if [ ${flags[$key]} -eq 1 ]; then
			printf "%-15s" "${key}"
		fi
	done
	echo
	index=0
	for itr in `seq 1 ${iterations}`
	do
		printf "$itr\t"
		for key in ${headers[@]}
		do
			if [ ${flags[$key]} -eq 1 ]; then
				value_list=(${values[$key]})
				printf "%-15s" "${value_list[${index}]}"
			fi
		done
		echo
		index=$(( $index + 1 ))
	done
	printf "Avg\t"
	for key in ${headers[@]}
	do
		if [ ${flags[$key]} -eq 1 ]; then
			printf "%-15s" "${averages[$key]}"
		fi
	done
	echo
}

iterations=10

declare -a headers=("native" "criu_appstart" "criu_response" "criu_scc" "openj9" "openj9_scc")
declare -A flags
for key in ${headers[@]}
do
	flags[$key]=0
done
declare -A values
declare -A averages
for key in ${headers[@]}
do
	averages[$key]=0
done

declare -a native_values criu_appstart_values criu_response_values criu_scc_values openj9_values openj9_scc_values

pre

if [ $# -ne 0 ]; then
	for arg in "$@";
	do
		case "$arg" in
		"native" | "criu_appstart" | "criu_response" | "criu_scc" | "openj9" | "openj9_scc")
			flags[$arg]=1
			;;
		"all")
			for key in ${headers[@]}
			do
				flags[$key]=1
			done
			;;
		*)
			echo "invalid argument $arg"
			exit 0
			;;
		esac
	done	
else
	for key in "${headers[@]}"
	do
		flags[$key]=1
	done
fi

for itr in `seq 1 ${iterations}`;
do
	for key in ${headers[@]}
	do
		flag=${flags[$key]}
		if [ ${flag} -eq 1 ]; then
			echo "###"
			echo "Iteration ${itr} for ${key}"
			test_${key}
		fi
	done
done

values[native]=${native_values[@]}
values[criu_appstart]=${criu_appstart_values[@]}
values[criu_response]=${criu_response_values[@]}
values[criu_scc]=${criu_scc_values[@]}
values[openj9]=${openj9_values[@]}
values[openj9_scc]=${openj9_scc_values[@]}

get_averages
print_summary

