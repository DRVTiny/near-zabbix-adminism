#!/bin/bash
[[ $1 == '-x' ]] && { shift; set -x; export TRACE=1; }

declare -r DFLT_BASE_BACKUP_DIR="$HOME/BB" \
	   BB_CMD='/usr/pgsql-13/bin/pg_basebackup' \
	   COMPRESSION_LEVEL=2
	   
tgt_bb_dir=${1:-${BASE_BACKUP_DIR:-$DFLT_BASE_BACKUP_DIR}}	   
tgt_bak_ymdhms="$tgt_bb_dir/$(date +'%Y%m%d-%H%M%S')"
[[ -d $tgt_bak_ymdhms ]] && rm -rf $tgt_bak_ymdhms
mkdir -p "$tgt_bak_ymdhms"

$BB_CMD \
	-c fast \
	-U replicator \
	-d postgresql://127.0.0.1:5432/zabbix \
	-D "$tgt_bak_ymdhms" \
	-Z${COMPRESSION_LEVEL} \
	-h 127.0.0.1 -p 5432 \
	-P \
	-F tar
	
