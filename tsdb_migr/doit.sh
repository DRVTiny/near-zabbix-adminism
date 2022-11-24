#!/bin/bash
[[ $1 == '-x' ]] && { shift; set -x; export TRACE=1; }
declare -r \
	DFLT_DAYS_BEFORE=7 \
	PG_DB=zabbix \
	PG_USER=zabbix \
	PG_HOST=zbx-db-pgbouncer \
	PG_PORT=6432 \
	ZBX_HOST=t-zbxdb03 \
	TIMED_OUT=124 \
	ERR_FAILED_TO_MANAGE_ZBX_SRV=17


errs=$(timeout 2 ssh $ZBX_HOST 'sudo systemctl status zabbix-server' 2>&1 >/dev/null)
if (( $? == TIMED_OUT )); then
	echo 'Failed to get status of zabbix-server. We have possible problems managing remote zabbix-server? Error: <<%s>>', "$errs" >&2
	exit $ERR_FAILED_TO_MANAGE_ZBX_SRV
fi

days_before=${1:-$DFLT_DAYS_BEFORE}
ts_now=$(date +%s)
ts_not_before=$(date -d "now-${days_before} days" +%s)

declare -a tmp_dirs=() tmp_files=()

fl_on_exit_set=

source <(sed -nr '/^# FUNCTIONS ->/, /^# <- FUNCTIONS/p' "$0")

temp_path tmp_dir_1st
for f in 1st/*.sql; do
	exec_psql "$f" $tmp_dir_1st TS_NOT_BEFORE $ts_not_before &
done
wait

ssh $ZBX_HOST 'sudo systemctl stop zabbix-server'

temp_path tmp_dir_2nd

for f in 2nd/*.sql; do
	exec_psql "$f" $tmp_dir_2nd TS_NEW_DATA $ts_now &
done
wait

psql_f 'fin/finish.sql'

ssh $ZBX_HOST 'sudo systemctl start zabbix-server; sleep 2; sudo systemctl status zabbix-server'

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

temp_path () {
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
# <- FUNCTIONS