#!/bin/bash

shopt -s extglob

logfile=out

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
	if [ -z "${JAVA_HOME}" ];
	then
		echo "JAVA_HOME is not set"
		exit 1
	fi
	if [ -z "${QUARKUS_APP_JAR}" ];
	then
		echo "QUARKUS_APP_JAR is not set"
		exit 1
	fi
	if [ -z "${QUARKUS_APP_NATIVE}" ];
	then
		echo "QUARKUS_APP_NATIVE is not set"
		exit 1
	fi
}

pre() {
	check_env

	rm -fr native criu openj9 openj9_scc
	mkdir -p native criu openj9 openj9_scc

	echo "Remove scc"
	${JAVA_HOME}/bin/java -Xshareclasses:name=c1,destroyAll &> /dev/null

	echo "Create scc"
	${JAVA_HOME}/bin/java -Xshareclasses:name=c1 -jar ${QUARKUS_APP_JAR} &> /dev/null &
	sleep 5s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null
}

native() {
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
}

criu() {
	logdir="criu"
	cdir=`pwd`

	rm -fr /root/quarkus/checkpoint
	mkdir -p /root/quarkus/checkpoint
	pushd /root/quarkus/checkpoint &>/dev/null

	setsid ${JAVA_HOME}/bin/java -jar ${QUARKUS_APP_JAR} </dev/null &>${logfile}.${itr} &
	sleep 5s
	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	/root/criu/scripts/criu-ns dump -t ${pid} --tcp-established -v3 -o dump.log

	sleep 1s

	${cdir}/hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	#echo "start: ${start}"
	/root/criu/scripts/criu-ns restore -d --tcp-established -v3 -o restore.log
	sleep 5s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logfile}.${itr} | head -n 1 | cut -d '=' -f 2`
	cp ${logfile}.${itr} ${cdir}/${logdir}
	echo "Start: ${start} End: ${end}"

	printf "criu: %s\n" $(datediff ${start} ${end})

	popd &>/dev/null
}

openj9() {
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
}

openj9_scc() {
	logdir="openj9_scc"

	./hit_url.sh &
	sleep 1s

	start=`date +"%T.%3N"`
	${JAVA_HOME}/bin/java -Xshareclasses:name=c1,readonly -jar ${QUARKUS_APP_JAR} &> ${logdir}/${logfile}.${itr} &
	sleep 5s

	pid=`ps -ef | grep getting-started | grep -v grep | awk '{ print $2 }'`
	echo "java pid: ${pid}"
	kill -9 ${pid} &>/dev/null

	end=`grep "End" ${logdir}/${logfile}.${itr} | head -n 1 | cut -d '=' -f 2`
	echo "Start: ${start} End: ${end}"

	#datediff "09:25:46.982" "09:25:47.009" #${start} ${end}
	printf "openj9_scc: %s\n" $(datediff ${start} ${end})
}

pre

for itr in `seq 1 10`;
do
	echo "###"
	echo "Iteration ${itr} for native"

	native

	echo "###"
	echo "Iteration ${itr} for criu"

	criu

	echo "###"
	echo "Iteration ${itr} for openj9"

	openj9

	echo "###"
	echo "Iteration ${itr} for openj9_scc"

	openj9_scc
done
