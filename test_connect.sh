#!/bin/sh
#                                                    #
# are necessary: stat awk grep curl ls wg 
# screen ./test_connect.sh config_file.conf
#                                                    #
g="\033[1;32m"       # green
r="\033[1;31m"       # red
n="\e[1;0m"          # normal
#                                                    #
IFACE="wg0"
WG_CONFIG="$1"
TMP_log="/tmp/$(basename $0).log"
DOMAINS_FILE="config/domains.lst"
CLIENT="./wg-client.sh"

ip_api="ip-api.com"
sec=900  			# 15 min = 900 sec
#                                                    #
# 1
check_size_log_file() {
	if [ -f "$TMP_log" ] && [ $(stat -c %s "$TMP_log") -ge 200 ]; then 
	             rm "$TMP_log"
        fi    
}
# 2            wc -c "$DOMAINS_FILE" | cut -d\  -f0
update_domains_lst() {
        if [ $(stat -c %s "$DOMAINS_FILE") -gt "$stat_size_file" ]; then
		echo -ne " Domain names have been ${g}"added"${n}". File updated." "
			"$CLIENT" update
        fi
}
# 3
delay_sec() {
N_sec=$1
        while [ $N_sec -ge 1 ]; do
                 N_sec=$((N_sec - 1))
          sleep 1
   	  echo -ne "   until the next check ${g}"$N_sec" ${n}"sec" \r"
	done
}
# 4
check_whois_expected_ip() { 
	curl --interface $IFACE $ip_api -s 
}
# 5
check_presence_CONFIG() {
	if [ ! -f "$WG_CONFIG" ]; then
    		echo -ne "\n${r}"Error:"${n}"" Config file "$WG_CONFIG" not found!\n" 
		echo -ne "\n${g}"Example:"${n}"" $0 config_file.conf\n\n" 
    	  exit 1  
  	fi
}
# 6
check_ip() {
        a=$(echo \
        ident.me \
        api.ipify.org \
        ifconfig.co \
        eth0.me \
        2ip.io \
        ifconfig.me \
        v4.i-p.show \
        wtfismyip.com \
        ifconfig.co \
        icanhazip.com \
        whatismyip.akamai.com \
        ipecho.net/plain \
        ipinfo.io/ip | \
        awk 'BEGIN { srand() } { split($0,a); print a[1+int(rand()*length(a))] }' )
        echo $a
}
# 7
main() {

  check_presence_CONFIG
  while
	expected_ip=`curl --interface $IFACE $(check_ip) -s`
        real_ip=`curl $(check_ip) -s`
        
        check_size_log_file
	
	if [ -z "$expected_ip" ]; then
                echo Reconnect `date '+%d-%B-%Y  %H-%M'` >> "$TMP_log"
		  "$CLIENT" restart "$WG_CONFIG"

	        elif [ "$real_ip" != "$expected_ip" ]; then
			echo -ne "\n\n "$real_ip" ${g}"*"${n}"" != "$expected_ip" ${r}"*"${n}" " \n\n"
                	echo $IFACE UP and connect - `date '+%d-%B-%Y  %H-%M'` >> "$TMP_log"
			stat_size_file=`stat -c %s "$DOMAINS_FILE"`
	fi

  check_whois_expected_ip
  delay_sec $sec           
  update_domains_lst
  clear
	there_is=`ls  /sys/class/net/ | grep "$IFACE" `
  [ "$IFACE" = "$there_is" ]; do true; done 

}

main