#!/bin/bash
# return if it was already sourced in the main script
[[ $flRunSourced ]] && return

declare -r 	binZbxSender='zabbix_sender' \
		binZbxGetter='zabbix_get' \
		pthSetEnvConf='/etc/zabbix/api/setenv.conf'
declare -r	ERR_GSSAPI_AUTH_FAILED=103 \
           	ERR_ZSERVER_NOT_DETERM=102 \
	   	ERR_HOST_NAME_UNRESOLVED=105

[[ -f $pthSetEnvConf && -r $pthSetEnvConf ]] && \
	source "$pthSetEnvConf"
		
dfltZbxServer=${ZBX_SERVER:-$(hostname -f)}
domain=${dfltZbxServer#*.}

flRunAsScript=''; flRunSourced=''
[[ ${BASH_SOURCE[0]} == $0 || -z ${BASH_SOURCE[0]} ]] && \
	flRunAsScript=1 			      || \
	flRunSourced=1

function norm3ze_host_name () {
	local hostName
	[[ $1 ]] || return 1
	[[ $1 =~ \. ]] && hostName=$1 || hostName="$1.$2"
	host $hostName &>/dev/null || return $ERR_HOST_NAME_UNRESOLVED
	echo "$hostName"
}

bin=''
if [[ $flRunAsScript ]]; then
	[[ $1 == '-x' ]] && {
		export TRACE=1 PS4='+(${BASH_SOURCE}: #${LINENO}): ${FUNCNAME[0]:-main}(): '
		shift
		set -x
	}
	
	declare -A name2bin=(
		['zsend']=$binZbxSender
		['zget']=$binZbxGetter
	)
	slf=${0##*/}
	bin=${name2bin[$slf]}
	
	pars="$@"
	[[ $pars =~ (--host|-s)[[:space:]]+([a-zA-Z0-9.-]+) ]] || { 
		$bin $@
		exit $?
	}

	hostName=$(norm3ze_host_name "${BASH_REMATCH[2]}" "$domain") || {
	        rc=$?
        	echo "ERROR: hostName is empty or it can not be resolved using DNS" >&2
	        exit $rc
	}

	[[ $slf == 'zsend' && $pars =~ (^|[[:space:]])-(-zabbix-server|z|-config|c) ]] && {
		$bin $@
		exit $?
	}
fi

declare -A memZbxSrv4Host
function getZbxSrv4Host () {
 local hostName=$(norm3ze_host_name "$1" "$domain") || {
 	local rc=$?
 	echo "ERROR: hostName is empty or it can not be resolved using DNS" >&2
 	return $rc
 } 
 
 local zserver
 case $DB_TYPE in
 postgresql)
	 zserver=$(sed -n '3s%^\s*%%p' <(
	   	   psql -U ${DB_USER:-$DB_LOGIN} -h ${DB_HOST} ${DB_NAME} <<EOSQL
SELECT 
	CASE p.hostid 
	WHEN NULL THEN '${dfltZbxServer}'
	ELSE p.host 
	END
FROM
	hosts h 
		LEFT JOIN hosts p ON h.proxy_hostid=p.hostid
WHERE h.host='${hostName}'
EOSQL
	))
 ;;
 mysql)
 	zserver=$(sed 1d <(mysql -u ${DB_USER:-$DB_LOGIN} -p"${DB_PASSWORD:-$DB_PASS}" -h ${DB_HOST} ${DB_NAME} <<EOSQL
SELECT 
	IF(p.hostid, '${dfltZbxServer}', p.host) zserver
FROM
	hosts h 
		LEFT JOIN hosts p ON h.proxy_hostid=p.hostid
WHERE h.host='${hostName}' 	
EOSQL
	))
 ;;
 esac
 
 if [[ ! $zserver || $zserver =~ \(0\ rows\) ]]; then
 	printf "ERROR: No host having name <<%s>> found in Zabbix\n" $hostName
 	return 104
 fi
 echo "$zserver"
}

function zsend () {
 local zbxSrv pars=$@
 shopt -s extglob
 if [[ $pars =~ (^|[[:space:]])-(-dry-run|t) ]]; then
 	echo -e "zsend called with parameters: $pars" >&2
 	[[ -t 0 ]] || echo -e 'zsend`s stdin: '"\n$(cat -)" >&2 	
 	return 0
 fi
 if [[ $pars =~ (^|[[:space:]])-(-zabbix-server|z|-config|c) || ! $pars =~ (--host|-s)[[:space:]]+([a-zA-Z0-9.-]+) ]]; then
 	[[ $pars =~ --memo(ize|ry) ]] && pars=${pars//@(--memoize|--memory)/}
 	$binZbxSender $pars
 	[[ $flRunAsScript ]] && exit $? || return $?
 fi
 
 local hostName=$(norm3ze_host_name "${BASH_REMATCH[2]}" "$domain") || {
        local rc=$?
        echo "ERROR: hostName is empty or it can not be resolved using DNS" >&2
        return $rc
 } 
 
 if [[ $pars =~ --memo(ize|ry) ]]; then
 	pars=${pars//@(--memoize|--memory)/}
 	zbxSrv=${memZbxSrv4Host[$hostName]}
 fi
 if [[ -z $zbxSrv ]]; then
 	zbxSrv=$(getZbxSrv4Host $hostName) || {
 		rc=$?
 		echo "$zbxSrv" >&2
 		exit $rc
 	}
 	[[ $zbxSrv ]] || return 1
	 memZbxSrv4Host[$hostName]=$zbxSrv
 fi
 $binZbxSender -z $zbxSrv $pars
 return $?
}

if [[ $flRunAsScript ]]; then
   case $slf in
         zget)
             realZbxServer=$(getZbxSrv4Host ${hostName}) || {
                rc=$?
                echo "$realZbxServer" >&2
                exit $rc
	     }

             [[ $realZbxServer && $realZbxServer != 'NULL' ]] || {
             	echo 'Zabbix server/proxy responsible for monitoring of the specified host was not determined by this script' >&2
	        exit $ERR_ZSERVER_NOT_DETERM
	     }
             if [[ $realZbxServer == $dfltZbxServer ]]; then
                $bin $@
             else

                klist | grep -q '^Default principal:' || { 	
                        kinit $(whoami)@${domain^^} || {
                           echo 'Cant get kerberos ticket for your current user!' >&2
                           exit $ERR_GSSAPI_AUTH_FAILED
                        }
                }
                ssh $realZbxServer "$bin $@"
                exit $?
             fi
         ;;
         zsend)
             zsend $@
             exit $?
         ;;
   esac
fi
