source ./psql_env.sh

psql_ () {
	local add_opts=''
	while [[ $# > 0 && $1 =~ ^- ]]; do
		if [[ $1 == '--' ]]; then
			shift
			break
		else
			add_opts+=" $1"
			shift
		fi
	done
	local what=$1
	local psql_cmd="psql -U ${PSQL_CONF[USER]} -p ${PSQL_CONF[PORT]} -h ${PSQL_CONF[SERVER]} ${add_opts} ${PSQL_CONF[DB]}"
	
	if [[ $what =~ \.sql$ ]]; then
		$psql_cmd <"$what"
	else
		$psql_cmd <<<"$what"
	fi 
}

psql_show () {
	local fmt
	[[ $# == 2 ]] && \
		{ fmt=$1; shift; } || \
		fmt=${PSQL_CONF[DFLT_FORMAT]}
		
	psql_ --$fmt "$1"
}

psql_show_html () {
	psql_show html "$1"
}

psql_show_csv () {
        psql_show csv "$1"
}
