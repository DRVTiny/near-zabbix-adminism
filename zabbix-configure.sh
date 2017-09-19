#!/bin/bash
#
# (C) by DRVTiny aka Andrey A. Konovalov, 2016
# License: GPLv2
#
# Please, install the following packages before using this script:
# libxml2-devel net-snmp-devel libssh2-devel gnutls-devel openldap-devel libcurl-devel 

sourcesPath=$(pwd)
declare -r ZBX_SRV_CONF='/etc/zabbix/zabbix_server.conf'
declare -A binaryType=(
	['server']=1
	['proxy']=1
	['agent']=0
)
declare -a binaryPath=('' '/sys')
declare -A opts=(
	['x']='flDebug'
	['a']='flActualizeCur'
	['s']='sourcesPath'
	['p']='soft'
	['v']='ver'
	['r']='flRemInstDir'
	['e']='flUseEnv'
	['b']='flUseBinSfx'
	['J']='flEnableJabber'
)

source '/opt/Libs/BASH/getopts_helper.inc'

[[ $flDebug ]] && set -x

if [[ $sourcesPath ]]; then
	[[ -d $sourcesPath ]] || {
		echo 'Wrong sourcesPath (-s parameter): not such directory' >&2
		exit 1
	}
	cd "$sourcesPath" || {
		echo "Cant cd into $sourcesPath, exiting" >&2
		exit 1
	}
fi

[[ -f configure && -x configure ]] || {
	printf 'Cant find configure script in "%s" or it is not executable\n' "$sourcesPath" >&2
	exit 2
}

dir=${PWD##*/}
[[ $ver ]]  || ver=${dir##*-}
[[ $soft ]] || soft=${dir%-*}
[[ $soft && $ver ]] || {
	echo 'Could not determine the software installation directory path automagically: please use "-p" and "-v" keys to specify your software name and/or version explicitly'
	exit 3
}

[[ $flUseEnv && $CFLAGS ]] || \
	export CFLAGS='-pipe -march=native -O3 -rdynamic'
	
basedir="/opt/$soft/self"
pfx="$basedir/$ver"

if [[ -d $pfx ]]; then
	if [[ $flRemInstDir ]]; then
		sudo rm -rf "$pfx" || {
			echo "Cant remove installation directory <<$pfx>>"
			exit 4
		}
	else
		echo "Installation path <<$pfx>> already exists, use '-r' key to remove it before installing"
		exit 4
	fi
fi
[[ $flUseBinSfx ]] && bin_sfx="-v${ver//./}"
[[ -d $pfx ]] && rm -rf "$pfx"
ncpus=$(nproc || fgrep -c processor /proc/cpuinfo)
make clean
./configure \
	--bindir="$pfx/Binaries" \
	--sbindir="$pfx/Binaries/sys" \
	--libexecdir="$pfx/Binaries/libexec" \
	--sysconfdir="$pfx/Configuration"  \
	--libdir="$pfx/Libraries" \
	--includedir="$pfx/Development/headers" \
	--datarootdir="$pfx/Datafiles/static" \
	--localstatedir="$pfx/Datafiles/dynamic" \
	--infodir="$pfx/Documentation/info-pages" \
	--mandir="$pfx/Documentation/man-pages" \
	--dvidir="$pfx/Documentation/dvi" \
	--htmldir="$pfx/Documentation/html" \
	--pdfdir="$pfx/Documentation/pdf" \
	--psdir="$pfx/Documentation/PostScript" \
	${bin_sfx:+--program-suffix="${bin_sfx}"} \
	--enable-server \
	--enable-proxy \
	--enable-agent \
	--disable-java \
	--with-mysql \
	--with-gnutls \
	--with-net-snmp \
	--with-ssh2 \
	--with-libxml2 \
	${flEnableJabber:+--with-jabber} \
	${flEnableIPMI:+--with-openipmi} \
	--with-ldap \
	--with-libcurl \
&& make -j${ncpus} \
&& sudo make install \
&& {
	[[ -d $pfx ]] && {
		echo "Creating symlink to original sources in <<$pfx/Development>> directory..." >&2
		[[ -d "$pfx/Development" ]] || sudo mkdir "$pfx/Development"
		sudo ln -s "$(pwd)" "$pfx/Development/sources"
		[[ $flActualizeCur ]] && { 
			echo "Actualizing <<current>> symlink in $basedir..." >&2
			[[ -L "$basedir/current" ]] && sudo rm -f "$basedir/current"
			sudo ln -s "$ver" "$basedir/current"
		}
		[[ $bin_sfx ]] && {
			echo 'Lets create symlinks from suffixed names to generic/normal/familiar ones' >&2
			for b in ${!binaryType[@]}; do
				dstPath="$pfx/Binaries${binaryPath[${binaryType[$b]}]}"
				[[ -f "${dstPath}/zabbix_${b}${bin_sfx}" ]] && \
					sudo ln -s "zabbix_${b}${bin_sfx}" "${dstPath}/zabbix_${b}"
			done
		}
		[[ -f $ZBX_SRV_CONF ]] && {
			confFile=${ZBX_SRV_CONF##*/}
			sudo mv "$pfx/Configuration/$confFile"{,.distr${bin_sfx}} && \
				sudo ln -s "${ZBX_SRV_CONF}" "$pfx/Configuration/"
		}
	}
}
