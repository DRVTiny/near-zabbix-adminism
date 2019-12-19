ldap_servers_by_domain () {
	local domain=$1
	local arrName=${2:-RESULT}
	[[ $domain ]] || {
		echo 'Specify LDAP domain where to search servers' >&2
		exit 1
	}
	printf 'declare -a %s=(%s)\n' "$arrName" "$(nslookup -query=srv _ldap._tcp.${domain} | sed -nr 's%^.*service\s*=\s*[0-9]+\s+[0-9]+\s+([0-9]+)\s+(.+).$%"\2:\1"%p' | tr '\n' ' ' | sed 's% $%%')"
}
