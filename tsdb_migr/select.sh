#!/bin/bash
source ./psql_funcs.sh
what2show=$1
[[ $what2show =~ \.sql$ ]] && \
	pfx=$(sed -r 's%^.*/%%; s%\.sql$%%' <<<"$what2show") || \
	pfx='select'
html_f=$(mktemp "/tmp/${pfx}_XXXXXXXXXXXX.html")
trap "rm -f \"$html_f\"" EXIT
psql_show_html "$what2show" > "$html_f"
elinks -dump -force-html "$html_f"
