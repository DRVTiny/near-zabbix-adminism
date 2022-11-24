#!/bin/bash
[[ $1 == '-x' ]] && { shift; set -x; export TRACE=1; }

> fin/drop_all_old_tables.sql
for t in 'history' 'trends'; do
	> fin/drop_old_${t}_tables.sql
done

for f in 1st/*.sql; do
	s=$(sed -r 's%\.sql$%%; s%^.*/%%' <<<"$f")
	sql_DROP="DROP TABLE IF EXISTS ${s}_old;"
	[[ $s =~ ^(history|trends) ]]
	t=${BASH_REMATCH[1]}
	echo "$sql_DROP" | tee -a fin/drop_all_old_tables.sql >> fin/drop_old_${t}_tables.sql
done
