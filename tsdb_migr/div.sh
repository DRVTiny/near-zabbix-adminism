#!/bin/bash
set -x
mkdir -p 1st 2nd
while read fwd; do
	echo "=====> $fwd <======"
	f=${fwd##*/}
#	sed -n '1,/ALTER TABLE/p' "$fwd" | sed '$d' > 1st/$f
	sed -n '/ALTER TABLE/,$p' "$fwd" > 2nd/$f
done < <(ls 1st_x/*.sql | fgrep -v finish)
