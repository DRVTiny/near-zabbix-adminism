#!/bin/bash
SECRET_FILE='/etc/zabbix/.backup_zabbix_config.secret'
declare -A src=(
	['host']='app-inzbxdb.dc.nspk.ru'
	['db']='zabbix'
	['user']='zabbixdit'
)
declare -A dst=(
	['host']=${src[host]}
	['db']="backup_zbx_conf_$(date +%Y%m%d%H%M)"
	['user']='root'
	['path']='/tmp'
)

doShowUsage () {
	cat <<EOUSAGE
Usage: 
	$0 -h | [-x] [-s SOURCE_DB_NAME] [-d DEST_DB_NAME] [-d DEST_PATH] [-e]	   
 	 -h		To show this message
 	 -x 		To turn on BASH trace mode
 	 -s 		Source database name represented as [hostName:]dbName (dbName="zabbix" by default)
 	 -d		Destination database name represented as [hostName:]dbName (dbName=="backup_zbx_conf_{%Y%m%d%H%M}" by default)
 	 -p		Destination path (directory where to place the dump file)
  	 -e 		Execute-flag: if set, script will connect to destination host and apply generated SQL
EOUSAGE
}

while getopts ':hs:d:p:ex' k; do
 case $k in
  x) export TRACE=1; set -x ;;
  s) 
  	if [[ $OPTARG =~ @ ]]; then
  		src['db']=${OPTARG%%@*}
  		user_host=${OPTARG#*@}
  		if [[ $user_host =~ : ]]; then
  			src['user']=${user_host%:*}
  			src['host']=${user_host##*:}
  		else
  			src['host']=$user_host
  		fi
  	else
  		src['db']=$OPTARG
  	fi
  ;;
  d)	if [[ $OPTARG =~ @ ]]; then
  		dst['db']=${OPTARG%%@*}
  		user_host=${OPTARG#*@}
  		if [[ $user_host =~ : ]]; then
  			dst['user']=${user_host%:*}
  			dst['host']=${user_host##*:}
  		else
  			dst['host']=$user_host
  		fi
  	else
  		dst['db']=$OPTARG
  	fi
  ;;
  p) 	dst['path']=$OPTARG	;;
  e) 	flExecute=1		;;
  h) 	doShowUsage; exit 0 ;;
  *) 	echo "Unknown option $k" >&2 ;;
 esac
done

source $SECRET_FILE || {
	echo "Cant source file ${SECRET_FILE} containing secrets aka database credentials" >&2
	exit 1
}
[[ ${src[db],,}'@'${src[host]} == ${dst[db],,}'@'${dst[host]} ]] && {
	echo 'Source and destination databases could not be the same' >&2
	exit 1
}
src['passwd']=${PASSWD[${src[user]}]}
[[ ${src[passwd]} ]] || {
	echo 'Dont know password to connect to source database' >&2
	exit 2
}

rxDataTables='^(alerts|history|event|acknowle|trend|logs|auditlog(_details)?)'
tblsZbxConfig=$( mysql -h ${src[host]} -u ${src[user]} -p"${src[passwd]}" -e 'show tables\G' ${src[db]} | \
			sed -nr 's%^[^:]+:\s*%%p' | egrep -v "$rxDataTables" )
  tblsZbxData=$( mysql -h ${src[host]} -u ${src[user]} -p"${src[passwd]}" -e 'show tables\G' ${src[db]} | \
			sed -nr 's%^[^:]+:\s*%%p' | egrep    "$rxDataTables" )
tData="('${tblsZbxData//$'\n'/','}')"

dumpFile="${dst[path]%/}/export_config_$(date +'%Y-%m-%d_%H:%M:%S').sql"
if [[ $flExecute ]]; then
	cmd='mysql -u root -p${PASSWD[root]}'
else
	cmd='cat -'
fi
exec 3<&1 1>"$dumpFile"
cat <<EOSQL | $cmd
DROP	DATABASE IF EXISTS ${dst[db]};
CREATE	DATABASE ${dst[db]} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

GRANT 	ALL PRIVILEGES ON ${dst[db]}.* TO 'zabbixdit'@'%'	IDENTIFIED BY '${PASSWD[zabbixdit]}';
-- GRANT SELECT ON	  ${dst[db]}.* TO 'zabbix'@'%' 		IDENTIFIED BY '${PASSWD[zabbix]}';
USE ${dst[db]};
EOSQL
#--set-gtid-purged=OFF
mysqldump -h ${src[host]} -u ${src[user]} -p"${src[passwd]}" --skip-triggers			${src[db]} $tblsZbxConfig
mysqldump -h ${src[host]} -u ${src[user]} -p"${src[passwd]}" --skip-triggers --no-data     	${src[db]} $tblsZbxData
cat <<EOSQL
DELETE FROM ids WHERE table_name IN $tData
EOSQL
exec 1<&3

echo "Saved to file: $dumpFile"

[[ $flExecute ]] && \
	mysql -h ${dst[host]} ${dst[db]} <"$dumpFile"
