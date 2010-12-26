#!/bin/bash +m

LOG=pingd.log
SCRIPTNAME=$(basename $0 .sh)
ALIVE=1
declare -a WORKERS

# UI functions
function start() {	
	# test if daemon is running
	if [[ -f $SCRIPTNAME.pid ]]; then
		echo "Demon ze tece! (pid $(cat $SCRIPTNAME.pid))"
		exit 1
	else
		pingd & 
		echo $! > $SCRIPTNAME.pid
		echo Demon zagnan!
		exit 0
	fi
}

function stop() {

	if [[ -f $SCRIPTNAME.pid ]]; then
		PID=$(cat $SCRIPTNAME.pid)
		kill -SIGUSR1 $PID
		rm -f $SCRIPTNAME.pid
		echo Demon ustavljen
	else
		echo Demon ne tece!
	fi
}

function restart() {
	stop
	start
}

function reload() {
		
	if [[ -f $SCRIPTNAME.pid ]]; then
		kill -SIGHUP $(cat $SCRIPTNAME.pid)
	else
		echo Demon ne tece!
	fi

}

function help() {
	echo Izpisem pomoc
}

function test() {

	rm -f $SCRIPTNAME.log $SCRIPTNAME.count $SCRIPTNAME.conf

	echo -e "www.google.com\t3\nwww.fri.uni-lj.si\t6" > $SCRIPTNAME.conf
	
	echo Zaganjam demona!
	start & 

	echo Spim za 10s
	sleep 10

	echo Dodajam IJS
	echo -e "www.ijs.si\t4" >> $SCRIPTNAME.conf

	reload &
	
	echo Spim za 10s
	sleep 10

	echo Ustavljam demona
	stop &

	wait

	#cat $SCRIPTNAME.log
	#echo USpesnih dostopov je bilo $(cat $SCRIPTNAME.count)

}

function inc {
	lockfile -1 $SCRIPTNAME.lock
	# kriticna sekcija
	COUNT=$( cat $SCRIPTNAME.count )
	let COUNT++
	echo $COUNT > $SCRIPTNAME.count
	# end kriticna sekcija
	rm -f $SCRIPTNAME.lock
	exit
}

function hostWorker() {

	OK=1
	HOST=$1
	DELAY=$2

	trap "echo $HOST dobil sem signal; OK=0" SIGHUP

	echo Preverjalnik $HOST deluje!

	while [[ -e $SCRIPTNAME.pid && $OK == 1 ]]; do

		sleep $DELAY &
		SLEEPPID=$!
		
		ping -c 1 $HOST &> /dev/null

		if [[ $? -eq 0 ]]; then
			logEvent "$HOST je dosegljiv!"
			inc &
		else
			logEvent "$HOST ni dosegljiv!"
		fi

		wait $SLEEPPID
	done;

	echo Preverjevelnik $HOST zakljucen!
}

function pingd() {

	trap "pingd_reload" SIGHUP
	trap "pingd_stop" SIGUSR1

	echo 0 > $SCRIPTNAME.count
	workers_start

	logEvent "$SCRIPTNAME started!"

	while [[ $ALIVE -eq 1 ]]; do
		sleep 1
	done
}

function pingd_reload() {
	logEvent "$SCRIPTNAME reloaded"
	workers_stop
	workers_start
}

function pingd_stop() {
	logEvent "$SCRIPTNAME stopped"
	workers_stop
	ALIVE=0
	wait
}

function workers_start() {
	i=1
	while read HOST DELAY; do
		#HOST=$(echo $LINE | awk '{print $1}')
		#DELAY=$(echo $LINE | awk '{print $2}')
		
		hostWorker $HOST $DELAY &
		WORKERS[$i]=$!

		let i++
	done < $SCRIPTNAME.conf
}

function workers_stop() {

	WORKERSCOUNT=${#WORKERS[@]}

	exec 10>&2 2>/dev/null #shranimo stderr v &10

	for ((i=1; i<=$WORKERSCOUNT; i++)); do
		# ubijemo delavce
		kill -SIGHUP ${WORKERS[$i]}
		wait ${WORKERS[$i]}
	done

	exec 2>&10- # restoramo stderr

	unset WORKERS
	declare -a WORKERS

}

function logEvent() {
	echo $(date +%Y-%m-%d" "%T) $1 >> $SCRIPTNAME.log
}


case $1 in

start)
	start
;;
stop)
	stop
;;
restart)
	restart
;;
reload)
	reload
;;
test)
	test
;;
*)
	help
;;
esac
