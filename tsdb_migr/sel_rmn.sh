#!/bin/bash
set -x
mkdir -p 1st 2nd
while read fwd; do
	echo "=====> $fwd <======"
	f=${fwd##*/}
	t=${f%.sql}
	sed -i "s%SELECT \* FROM%INSERT INTO $t &%" "$fwd"
done < <(ls 2nd/*.sql | fgrep -v finish)
