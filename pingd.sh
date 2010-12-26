#!/bin/bash

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

	wait $!


	cat $SCRIPTNAME.log

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
	DELAY=${2:-"5"}

	trap "sleep 1; OK=0; logEvent \"Preverjalnik $HOST se je zakljucil\"; sleep 1" SIGUSR2

	while [[ $OK -eq 1 ]]; do
		sleep $DELAY &
		SLEEPPID=$!

		ping -c 1 $1 &> /dev/null
		if [[ $? -eq 0 ]]; then
			logEvent "$HOST je dosegljiv!"
			inc &
		else
			logEvent "$HOST ni dosegljiv!"
		fi

		wait $SLEEPPID
	done;
}

function pingd() {

	trap "pingd_reload" SIGHUP
	trap "pingd_stop" SIGUSR1

	echo 0 > $SCRIPTNAME.count
	workers_start

	logEvent "Startal sem demona"

	while [[ $ALIVE -eq 1 ]]; do
		sleep 1
	done
}

function pingd_reload() {
	logEvent "Reloadam demona"
	workers_stop
	workers_start
}

function pingd_stop() {
	logEvent "Ustavljam demona"
	workers_stop
	wait
	ALIVE=0
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

	for ((i=1; i<=$WORKERSCOUNT; i++)); do
		echo Ubijemo ${WORKERS[$i]}	
		# ubijemo delavce
		kill -SIGUSR2 ${WORKERS[$i]}
	done

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
