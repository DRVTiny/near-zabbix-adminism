#!/bin/bash
declare -r \
	DFLT_DAYS_BEFORE=7 \
	PGBOUNCER_HOST=10.8.123.141 \
	PGBOUNCER_PORT=6432
	
days_before=${1:-$DFLT_DAYS_BEFORE}
ts_start=$(date +%s)
ts_not_before=$(date -d "now-${days_before} days" +%s)
echo $ts_not_before > 1st.ts
tmp_dir=$(mktemp -d /tmp/XXXXXXX)
cp -r 1st $tmp_dir

declare -a sqls=($(ls $tmp_dir/*.sql | fgrep -v finish))
while read f; do
	sed -ri 's%\$TS_NOT_BEFORE%'"$ts_not_before%" "$f"
done

time parallel "psql -U zabbix -h $PGBOUNCER_HOST -p $PGBOUNCER_PORT zabbix <{}"  ::: ${sqls[@]}

