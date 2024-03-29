opt_dscr=':'
opt_help=''

opt_show_usage () {
	cat >&2 <<USAGE
Usage:
	${0##*/} <options>
Possible options are:
${opt_help:0:-1}
USAGE
}

[[ ${opts['h']} ]] || opts['h']='&opt_show_usage; exit 0 {Show this useful message}'

for opt_k in $(echo "${!opts[@]}" | sort); do
	opt_dscr+=${opt_k}
	v=${opts[${opt_k}]}
	descr_text=
	if [[ $v =~ [[:space:]]\{(.+)\}$ ]]; then
		descr_text=${BASH_REMATCH[1]}
		v=${v:0:$((${#v}-${#descr_text}-1-2))}
		opts[${opt_k}]=$v
	fi
	opt_help+=$'\t'"-${opt_k}"
	fl_with_val=
	if ! [[ ${v:0:2} == 'fl' || ( ${v:0:1} == '&' && ${v/\$OPTARG/} == $v ) ]]; then
		opt_dscr+=':'
		opt_help+=' <VALUE>'
		fl_with_val=' '
	fi
	[[ $descr_text ]] && opt_help+=${fl_with_val:-$'\t'}$'\t'"${descr_text}"
	# set default values for variables
	if [[ $v =~ ^([a-zA-Z_][a-zA-Z0-9_]*(\[[^]]+\])?)=(.*)$ ]]; then
		opt_help+=" (default: ${BASH_REMATCH[3]})"
		eval "$v"
	fi
	opt_help+=$'\n'
done

declare -F err_ &>/dev/null || {
	err_ () {
		echo "$@" >&2
		opt_show_usage
		exit 103
	}
}

keys_used=''
while getopts $opt_dscr k; do
	v=${opts[$k]}
	if [[ ! $v  ]]; then
		if [[ $k == '?' ]]; then
			err_ "No such option '-${OPTARG}'"
		else
			err_ "'-$k' not implemented yet"
		fi
		exit 1
	fi
	if [[ ${v:0:1} == '&' ]]; then
		eval "${v:1}"
	# if option accepts argument
	elif [[ $opt_dscr =~ ${k}: ]]; then
		echo "${v%%=*}=\$OPTARG"
		eval "${v%%=*}=\$OPTARG"
	else
		eval "${v%%=*}=1"
	fi
	keys_used+=$k
done
