#!/bin/bash
#
# (C) by Andrey A. Konovalov aka DRVTiny, NSPK, 2016-2017
#
# Steps of execution:
# 	1. Download certificate within specified location (host:port)
# 	2. Parse certificate to get/know url's for CA certificate and CRL
# 	3. Download CA certificate and CRL file by urls extracted on step 2
# 	4. Check certificate expire date  (require CA certificate)
# 	5. Check certificate revocation status (require CA certificate and CRL)
#
# Send your questions and suggestions to drvtiny@gmail.com. Thank you for using this script!
#

# Defaults ->
# Default (fallback) CA certificate file. If the valid path to the CA cert should be found in the downloaded server certificate, this variable will be replaced.
pemCACert='/opt/Zabbix/x509/sca.cer'
agentConf='/etc/zabbix/zabbix_agentd.conf'
# <- Defaults

[[ $1 == '-x' ]] && { set -x; export TRACE=1; }
err_ () {
	echo "ERROR: $0: @$(date +%s): $@" >&2
}

declare -r PROXY_SETTINGS='/etc/profile.d/proxy.sh'
declare -A err2msg=(
	['ERR_INVALID_OPTION']='Invalid option passed to me'
	['ERR_INC_FILE_NOT_FOUND']='Include file not found'
	['ERR_TMP_DIR_FAIL']='Failed to create and use temporary directory'
	['ERR_WEB_CON_REFUSED']='Connection to web-server was refused'
	['ERR_CANT_GET_CRL']='Cant download CRL'
	['ERR_CANT_GET_CA_CERT']='Failed to download CA certificate'
	['ERR_CANT_GET_REF_OBJ']='Cant get some object referred by URI in the server certificate'
	['ERR_CMN_SSL_ERR']='OpenSSL-related issue'
	['ERR_ZBX_SND_FAIL']='Zabbix sender failed'
	['ERR_LDAP_URL_PROBLEM']='Problem while fetching some data specified by LDAP url inside the certificate'
	['ERR_REF_OBJ_URI_IS_EMPTY']='Referred object URI is empty'
	['ERR_UNKNOWN_REF_OBJ_TYPE']='Unknown referred object type'
)

slf_base_path=$(readlink -e "$0")
declare -A slf=(
	[real_dir]=$(dirname "$slf_base_path")
	[real_file]=$slf_base_path
	[dir]=$(dirname "$0")
	[file]=$0
)

declare -A host=(
	['CertName']='support.example.com'
	['ZbxHost']='redmine01.example.com'
)

declare -A opts=(
	['s']='host["CertName"] {Host name as specified in certificate`s CN}'
	['z']='host["ZbxHost"] {Zabbix host to receive certificate check metrics}'
	['p']='sslPort {Number of SSL TCP port to use}'
	['x']='flTrace {Turn on BASH-tracing feature (i.e. set -x)}'
	['i']='flIgnoreCAInCert {Ignore CA certificate url specified in certificate, use our own copy of CA certificate}'
	['D']='flDontRemoveTmp {Do not remove temporary directory containing intermediate certificate processing results}'
	['t']='flDryRun {Do not try to send anything to Zabbix, just show some useful debug info}'
)

declare -A libs=(
	['getopts_helper']='R'
	['erc_handle']='R'
	['ldap']='O'
	['domain_creds']='O'
	['zbx_get_and_send']='R'
)

inc_path="${slf[real_dir]}/inc"
for lib in ${!libs[@]}; do
	inc_file="${inc_path}/${lib}.inc"
	if [[ -f $inc_file ]]; then
		source "$inc_file"
	elif [[ ${libs[$lib]} == 'R' ]]; then
		err_ "library $lib required, but not found in ${inc_path}"
		exit $ERR_INC_FILE_NOT_FOUND
	else
		err_ "library $lib not found, but its considered optional, so we my skip it"
	fi
done

if [[ $flDryRun && $flDryRun == 1 ]]; then
	dryRunOpt='--dry-run'
else
	dryRunOpt=''
fi

[[ $(env) =~ (https?_proxy|HTTPS?_PROXY) ]] || {
        [[ -f $PROXY_SETTINGS && -r $PROXY_SETTINGS ]] && \
                source $PROXY_SETTINGS	
}

trace () {
	echo "+${BASH_SOURCE[1]}:${BASH_LINENO[0]}:${FUNCNAME[1]}:${BASH_COMMAND}"
}

[[ $flTrace && ! $TRACE ]] && {
	set -x
#	set -o functrace
#	shopt -s extdebug
#	trap trace DEBUG
	export TRACE=1
}

[[ $keys_used =~ [sz]  ]] && {
	[[ ${keys_used/s/} == $keys_used ]]; flUseZbxH=$?
	[[ ${keys_used/z/} == $keys_used ]]; flUseCertH=$?
	if ! [[ $flUseZbxH -ne 0 && $flUseCertH -ne 0 ]]; then
		if [[ $flUseZbxH -eq 0 ]]; then
			host['CertName']=${host[ZbxHost]}
		else
			host['ZbxHost']=${host[CertName]}
		fi
	fi
}

hook_on_exit () {
	local erc=$1 msg=$2
	
	if (( erc )); then
	# Dont try to use zabbix_sender if we are here because of its failure!
		(( (erc&255) == ERR_ZBX_SND_FAIL )) && return 0
		zsend $dryRunOpt --memoize -vv -s ${host[ZbxHost]} -i - <<ITEMS
- check.cert.script_status $erc
- check.cert.last_err_txt "$msg"
ITEMS
	else
		zsend $dryRunOpt --memoize -vv -s ${host[ZbxHost]} -o 0 -k 'check.cert.script_status'
	fi
	return 0
}

sslHost=${host[CertName]}
pemCert="${sslHost}_cert.pem"
derCRL="${sslHost}_crl.der"
pemCRL=${derCRL/.der/.pem}

tmpDir=$(mktemp -d /tmp/XXXXXXXXXX)
echo "Using temporary directory: $tmpDir" >&2
try $ERR_TMP_DIR_FAIL cd "$tmpDir" 4>/dev/null

[[ $flDontRemoveTmp ]] || \
	cleanOnExit "$tmpDir"
	
set -o pipefail
sslPort=${sslPort:-$(getent services https | sed -nr 's%^.*\s([0-9]+).*$%\1%p')}
zbxHost=${host[ZbxHost]}
ldapDomain=${sslHost#*.}
##try -e '[[ $retc>0 && $retc<100 ]]' $ERR_WEB_CON_REFUSED 
#timeout 1 telnet $sslHost $sslPort 4>/dev/null
#if [[ $?>0 && $?<100 ]]; then
#	err_ "Cant connect to $sslHost:$sslPort, connection refused"
#	exit $ERR_WEB_CON_REFUSED
#fi
get_ldap_cert () {
	local url=$1 domain=$2 creds
	
	if [[ $url =~ ldaps?:/// ]]; then
		until [[ $domain ]]; do
			echo -n 'Input your LDAP domain: '; read domain; echo
		done
		source <( ldap_servers_by_domain "$domain" ldapServers )
		(( ${#ldapServers[@]} )) || {
			echo "Cant determine LDAP servers for domain ${domain}" >&2
			exit $ERR_LDAP_URL_PROBLEM
		}
		url=$(echo "$url" | sed -r "s%(ldaps?):///%\1://${ldapServers[0]}/%")
	else
		[[ $url =~ ldaps?://([^/]+)/ ]]
		domain=${BASH_REMATCH[1]#*.}
		[[ $domain ]] || {
			echo 'Cant determine domain from your LDAP URL' >&2
			exit $ERR_LDAP_URL_PROBLEM
		}
	fi
	domain=${domain,,}
	creds=${creds4dmn[$domain]}
	certObj=$(curl ${creds:+-u "$creds"} "$url")
	if [[ $certObj =~ cACertificate::[[:space:]](.+)$ ]]; then
		echo -e "-----BEGIN CERTIFICATE-----\n${BASH_REMATCH[1]}\n-----END CERTIFICATE-----" | fold -w64
	elif [[ $certObj =~ certificateRevocationList:: ]]; then
		echo "$certObj" | sed -nr 's%^\s*certificateRevocationList::\s(.+)$%\1%p' | base64 -d | openssl crl -inform DER
	else
		exit $ERR_UNKNOWN_REF_OBJ
	fi
}

get_file_by_url () {
	local url=$1 host_domain=$2 alt_fname=$3 
	local der_name
	[[ $url ]] || exit $ERR_REF_OBJ_URI_IS_EMPTY
	if [[ $url =~ ldaps?:// ]]; then
		out_fname=$alt_fname
		get_ldap_cert "$url" "$host_domain" > "$out_fname"
	else
		out_fname=${url##*/}
		try $ERR_CANT_GET_REF_OBJ timeout 4 wget -q "$url" -O "$out_fname"
		[[ $out_fname =~ \.pem$ ]] || {
			der_name=$out_fname
			out_fname="${out_fname%.*}.pem"
			try $ERR_CMN_SSL_ERR openssl x509 -in "$der_name" -inform DER -out "$out_fname"
		}
	fi
	echo "$out_fname"
}

openssl s_client -showcerts -servername $sslHost -connect $sslHost:$sslPort <<<'' 2>/dev/null | \
	openssl x509 -inform pem -text > "$pemCert"
urlCRL=$(sed -nr '/CRL Distribution Points:/,${ s%^\s+URI:((ldap|http)s?:.+)$%\1%p; T l; q; :l }' "$pemCert") && \
	pemCRL=$(get_file_by_url "$urlCRL" "$ldapDomain" 'crl.pem')
	
if [[ $flIgnoreCAInCert ]]; then
	flIgnoreCAInCert=' '
else
	urlCACrt=$(sed -nr 's%^\s*CA Issuers.+URI:((http|ldap)s?:.+)\s*$%\1%pI; T l; q; :l' "$pemCert") && \
		pemCACrt=$(get_file_by_url "$urlCACrt" "$ldapDomain" 'ca_cert.pem')
fi

openssl verify ${flIgnoreCAInCert:--CAfile "$pemCACrt"} -CRLfile "$pemCRL" "$pemCert"
checkCRLStatus=$?

tsCertValidTill=$(date -d "$(sed -nr 's%^\s+Not After\s+:\s+%%p' $pemCert)" +%s)
secsBeforeCertExpire=$((tsCertValidTill-$(date +%s)))

try $ERR_ZBX_SND_FAIL zsend $dryRunOpt --memoize -vv -s ${host[ZbxHost]} -i - <<ITEMS
- check.cert.time_before_expiration $secsBeforeCertExpire
- check.cert.revoke_status $checkCRLStatus
ITEMS
