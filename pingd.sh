#!/bin/bash

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
		#rm -f $SCRIPTNAME.pid
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
	cat << LOL
Usage:
	$0 (start | stop | reload | restart )

	start:
		Starts a daemon
	stop:
		Stops daemon
	reload:
		Force reload of onfiguration files
	restart:
		stop(); start()

Files:
	$SCRIPTNAME.sh: Daemon script
	$SCRIPTNAME.conf: Configuration files, each line is one host. First field is hostname, then TAB then pause between probes
	$SCRIPTNAME.count: Number of successful probes
	$SCRIPTNAME.log: Log file
	$SCRIPTNAME.pid: Pid of daemon. Hands off!
	$SCRIPTNAME.lock: Semaphore. Hands off!

Description:
	$SCRIPTNAME is daemon, which periodicaly checks for hosts, if they respond to ping request and log it to log file.

LOL
}

function test() {

	rm -f $SCRIPTNAME.log $SCRIPTNAME.count $SCRIPTNAME.conf

	echo -e "www.google.com\t3\nwww.fri.uni-lj.si\t6" > $SCRIPTNAME.conf
	
	echo Zaganjam demona!
	$0 start 

	PID=$(cat $SCRIPTNAME.pid)

	echo Spim za 15s
	sleep 15

	echo Dodajam IJS
	echo -e "www.ijs.si\t4" >> $SCRIPTNAME.conf

	$0 reload
	
	echo Spim za 15s
	sleep 15

	echo Ustavljam demona
	$0 stop

	while [[ -e $SCRIPTNAME.pid || -e $SCRIPTNAME.lock ]]; do
		sleep 1
	done

	echo "###########################################"
	cat $SCRIPTNAME.log
	echo Uspesnih dostopov je bilo $(cat $SCRIPTNAME.count)

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

	trap "OK=0" SIGHUP

	logEvent "pinger $HOST started!"

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

	logEvent "pinger $HOST stopped!"
}

function pingd() {

	trap "pingd_reload" SIGHUP
	trap "pingd_stop" SIGUSR1

	echo 0 > $SCRIPTNAME.count
	workers_start

	logEvent "$SCRIPTNAME started!"

	while [[ -e $SCRIPTNAME.pid && $ALIVE -eq 1 ]]; do
		sleep 1
	done

	logEvent "$SCRIPTNAME stopped"
	rm -f $SCRIPTNAME.pid
	exit 0
}

function pingd_reload() {
	workers_stop
	workers_start
	logEvent "$SCRIPTNAME reloaded"
}

function pingd_stop() {
	workers_stop
	ALIVE=0
}

function workers_start() {
	i=1
	while read HOST DELAY; do
		hostWorker $HOST $DELAY &
		WORKERS[$i]=$!
		let i++
	done < $SCRIPTNAME.conf
}

function workers_stop() {

	WORKERSCOUNT=${#WORKERS[@]}

	#exec 10>&2 2>/dev/null #shranimo stderr v &10

	for ((i=1; i<=$WORKERSCOUNT; i++)); do
		# ubijemo delavce
		if [[ `kill -0 ${WORKERS[$i]}` -eq 0 ]]; then
			kill -SIGHUP ${WORKERS[$i]}
			wait ${WORKERS[$i]}
		fi
	done

	#exec 2>&10- # restoramo stderr

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
