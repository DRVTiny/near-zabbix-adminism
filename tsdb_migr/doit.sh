#!/bin/bash
[[ $1 == '-x' ]] && { shift; set -x; export TRACE=1; }
declare -r \
	SSH_OP_TIMEOUT=2 \
	DFLT_DAYS_BEFORE=7 \
	PG_DB=zabbix \
	PG_USER=zabbix \
	PG_HOST=zbx-db-pgbouncer \
	PG_PORT=6432 \
	ZBX_HOST=kv-zbx-app01 \
	TIMED_OUT=124 \
	ERR_FAILED_TO_MANAGE_ZBX_SRV=17 \
	ERR_ZABBIX_NOT_RUNNING=19 \
	ERR_FAIL_TO_STOP_SVCS=21 \
	ERR_FAIL_TO_START_ZBX_SRV=23 \
	ERR_INTERRUPTED_BY_USER=25
	
declare -Ar SVC=(
	['server']='zabbix-server'
	['frontend']='rh-nginx116-nginx'
)

errs=$(timeout $SSH_OP_TIMEOUT ssh $ZBX_HOST 'sudo systemctl status '${SVC[server]} 2>&1 >/dev/null)
erc=$?
if (( erc == TIMED_OUT )); then
	echo 'Failed to get status of zabbix-server. We have possible problems managing remote zabbix-server? Error: <<%s>>', "$errs" >&2
	exit $ERR_FAILED_TO_MANAGE_ZBX_SRV
elif (( erc )); then
	printf 'zabbix-server on %s is not in active state\n' $ZBX_HOST >&2
	exit $ERR_ZABBIX_NOT_RUNNING
fi

days_before=${1:-$DFLT_DAYS_BEFORE}
ts_now=$(date +%s)
ts_not_before=$(date -d "now-${days_before} days" +%s)

declare -a tmp_dirs=() tmp_files=()

fl_on_exit_set=

source <(sed -nr '/^# FUNCTIONS ->/, /^# <- FUNCTIONS/p' "$0")

get_temp_path_to tmp_dir_1st

# PART I: WITHOUT DOWNTIME ->
for f in 1st/*.sql; do
	exec_psql "$f" $tmp_dir_1st TS_NOT_BEFORE $ts_not_before &
done
wait
# <- PART I: WITHOUT DOWNTIME

read_YN 'Next part is DANGEROUS and will lead to potentially VERY LONG DOWNTIME. Continue?'

# PART 2: WITH !!!__DOWNTIME__!!! ->
if ! ssh $ZBX_HOST $(printf 'sudo systemctl stop %s %s' ${SVC[frontend]} ${SVC[server]}); then
	echo "Failed to stop ${SVC[frontend]}, ${SVC[server]} on $ZBX_HOST" >&2
	exit $ERR_FAIL_TO_STOP_SVCS
fi

get_temp_path_to tmp_dir_2nd

for f in 2nd/*.sql; do
	exec_psql "$f" $tmp_dir_2nd TS_NEW_DATA $ts_now &
done
wait

psql_f 'fin/finish.sql'
# <- PART 2: WITH !!!__DOWNTIME__!!!

if ssh $ZBX_HOST "sudo systemctl start ${SVC[server]}; sleep 2; sudo systemctl status ${SVC[server]}"; then
	ssh $ZBX_HOST "sudo systemctl start ${SVC[frontend]}"
else
	echo "Failed to start service ${SVC[server]} on $ZBX_HOST, you may need to read <<ssh $ZBX_HOST 'sudo systemctl status -l ${SVC[server]}'>> output for more info" >&2
	exit $ERR_FAIL_TO_START_ZBX_SRV
fi

exit $?

# FUNCTIONS ->
clean_on_exit () {
	local d f
	for d in ${tmp_dirs[@]}; do
		echo "removing temporary dir $d" >&2
		rm -rf "$d" 
	done
	for f in ${tmp_files[@]}; do
		echo "removing temporary file $f" >&2
		rm -f "$f" 
	done
}

get_temp_path_to () {
	[[ $fl_on_exit_set ]] || {
		trap clean_on_exit EXIT
		fl_on_exit_set=1
	}
	local v=$1
	local td=$(mktemp -d /tmp/XXXXXXXXXXXX)
	eval "$v=$td"
}

psql_f () {
	psql -U $PG_USER -h $PG_HOST -p $PG_PORT $PG_DB <"$1"
}

exec_psql () {
	local templ_file=$1 tmp_dir=$2; shift 2
	local tmpr_file="${tmp_dir}/${templ_file##*/}"
	cp "$templ_file" "$tmpr_file"
	while (( $# )); do
		sed -i "s%\$${1}%$2%g" "$tmpr_file"
		shift 2
	done
	psql_f "$tmpr_file"
}

read_YN () {
	local yn
	local prompt=${1:-Do you want to proceed?}
	while :; do
		read -p "$prompt (yes/no) " yn
		case ${yn,,} in 
			y*) 
				echo 'OK, continue processing' >&2
				break
			;;
			n*)
				echo 'Exiting...' >&2
				exit $ERR_INTERRUPTED_BY_USER
			;;
			*) 
				echo 'Invalid response, try again' >&2
			;;
		esac
	done
}
# <- FUNCTIONS