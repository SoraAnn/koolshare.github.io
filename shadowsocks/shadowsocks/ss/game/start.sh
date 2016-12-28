#!/bin/sh
#--------------------------------------------------------------------------------------
# Variable definitions
eval `dbus export ss`
source /koolshare/scripts/base.sh
alias echo_date='echo $(date +%Y年%m月%d日\ %X):'
ss_basic_password=`echo $ss_basic_password|base64_decode`
CONFIG_FILE=/koolshare/ss/game/ss.json
#--------------------------------------------------------------------------------------
resolv_server_ip(){
	IFIP=`echo $ss_basic_server|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
	if [ -z "$IFIP" ];then
		echo_date 检测到你的SS服务器为域名格式，将尝试进行解析...
		if [ "$ss_basic_dnslookup" == "1" ];then
			echo_date 使用nslookup方式解析SS服务器的ip地址,解析dns：$ss_basic_dnslookup_server
			server_ip=`nslookup "$ss_basic_server" $ss_basic_dnslookup_server | sed '1,4d' | awk '{print $3}' | grep -v :|awk 'NR==1{print}'`
		else
			echo_date 使用resolveip方式解析SS服务器的ip地址.
			server_ip=`resolveip -4 -t 2 $ss_basic_server|awk 'NR==1{print}'`
		fi

		if [ ! -z "$server_ip" ];then
			echo_date SS服务器的ip地址解析成功：$server_ip.
			ss_basic_server="$server_ip"
			dbus set ss_basic_server_ip="$server_ip"
			dbus set ss_basic_dns_success="1"
		else
			echo_date SS服务器的ip地址解析失败，将由ss-redir自己解析.
			dbus set ss_basic_dns_success="0"
		fi
	else
		echo_date 检测到你的SS服务器已经是IP格式：$ss_basic_server,跳过解析... 
	fi
}
# create shadowsocks config file...
creat_ss_json(){
	[ $ss_basic_onetime_auth -ne 1 ] && ARG_OTA="" || ARG_OTA="-A";
	if [ "$ss_basic_ss_obfs_host" != "" ];then
		if [ "$ss_basic_ss_obfs" == "http" ];then
			ARG_OBFS="--obfs http --obfs-host $ss_basic_ss_obfs_host"
		elif [ "$ss_basic_ss_obfs" == "tls" ];then
			ARG_OBFS="--obfs tls --obfs-host $ss_basic_ss_obfs_host"
		else
			ARG_OBFS=""
		fi
	else
		if [ "$ss_basic_ss_obfs" == "http" ];then
			ARG_OBFS="--obfs http"
		elif [ "$ss_basic_ss_obfs" == "tls" ];then
			ARG_OBFS="--obfs tls"
		else
			ARG_OBFS=""
		fi
	fi
	echo_date 创建SS配置文件到$CONFIG_FILE
	if [ "$ss_basic_use_rss" == "0" ];then
		cat > $CONFIG_FILE <<-EOF
			{
			    "server":"$ss_basic_server",
			    "server_port":$ss_basic_port,
			    "local_port":3333,
			    "password":"$ss_basic_password",
			    "timeout":600,
			    "method":"$ss_basic_method"
			}
		EOF
	elif [ "$ss_basic_use_rss" == "1" ];then
		cat > $CONFIG_FILE <<-EOF
			{
			    "server":"$ss_basic_server",
			    "server_port":$ss_basic_port,
			    "local_port":3333,
			    "password":"$ss_basic_password",
			    "timeout":600,
			    "protocol":"$ss_basic_rss_protocol",
			    "obfs":"$ss_basic_rss_obfs",
			    "obfs_param":"$ss_basic_rss_obfs_param",
			    "method":"$ss_basic_method"
			}
		EOF
	fi
}
#--------------------------------------------------------------------------------------
creat_dnsmasq_basic_conf(){
	ISP_DNS=$(nvram get wan0_dns|sed 's/ /\n/g'|grep -v 0.0.0.0|grep -v 127.0.0.1|sed -n 1p)
	[ "$ss_game_dns_china" == "1" ] && [ ! -z "$ISP_DNS" ] && CDN="$ISP_DNS"
	[ "$ss_game_dns_china" == "1" ] && [ -z "$ISP_DNS" ] && CDN="114.114.114.114"
	[ "$ss_game_dns_china" == "2" ] && CDN="223.5.5.5"
	[ "$ss_game_dns_china" == "3" ] && CDN="223.6.6.6"
	[ "$ss_game_dns_china" == "4" ] && CDN="114.114.114.114"
	[ "$ss_game_dns_china" == "5" ] && CDN="$ss_game_dns_china_user"
	[ "$ss_game_dns_china" == "6" ] && CDN="180.76.76.76"
	[ "$ss_game_dns_china" == "7" ] && CDN="1.2.4.8"
	[ "$ss_game_dns_china" == "8" ] && CDN="119.29.29.29"

	# make directory if not exist
	mkdir -p /jffs/configs/dnsmasq.d

	# append dnsmasq basic conf
	echo_date 创建dnsmasq基础配置到/jffs/configs/dnsmasq.conf.add
	cat > /jffs/configs/dnsmasq.conf.add <<-EOF
		no-resolv
		server=127.0.0.1#1053
	EOF

	# append router output chain rules
	echo_date 创建路由内部走代理的规则，用于SS状态检测.
	cat /koolshare/ss/redchn/output.conf >> /jffs/configs/dnsmasq.conf.add

	# append china site
	echo_date 生成cdn加速列表到/tmp/sscdn.conf，加速用的dns：$CDN
		rm -rf /tmp/sscdn.conf
		echo "#for china site CDN acclerate" > /tmp/sscdn.conf
		cat /koolshare/ss/redchn/cdn.txt | sed "s/^/server=&\/./g" | sed "s/$/\/&$CDN/g" | sort | awk '{if ($0!=line) print;line=$0}' >>/tmp/sscdn.conf

	# create dnsmasq postconf
	echo_date 创建dnsmasq.postconf软连接到/jffs/scripts/文件夹.
		#cp /koolshare/ss/redchn/dnsmasq.postconf /jffs/scripts/dnsmasq.postconf
		ln -sf /koolshare/ss/redchn/dnsmasq.postconf /jffs/scripts/dnsmasq.postconf
		chmod +x /jffs/scripts/dnsmasq.postconf

}

custom_dnsmasq(){
	if [ ! -z "$ss_game_dnsmasq" ];then
		echo_date 添加自定义dnsmasq设置到/tmp/custom.conf
		echo "$ss_game_dnsmasq" | base64_decode | sort -u >> /tmp/custom.conf
	fi
}

ln_conf(){
	rm -rf /jffs/configs/dnsmasq.d/cdn.conf
	if [ -f /tmp/sscdn.conf ];then
		echo_date 创建cdn加速列表软链接/jffs/configs/dnsmasq.d/cdn.conf
		ln -sf /tmp/sscdn.conf /jffs/configs/dnsmasq.d/cdn.conf
	fi
	rm -rf /jffs/configs/dnsmasq.d/custom.conf
	if [ -f /tmp/custom.conf ];then
		echo_date 创建自定义dnsmasq配置软链接/jffs/configs/dnsmasq.d/custom.conf
		ln -sf /tmp/custom.conf /jffs/configs/dnsmasq.d/custom.conf
	fi
}

#--------------------------------------------------------------------------------------
nat_auto_start(){
	mkdir -p /jffs/scripts
	# creating iptables rules to nat-start
	if [ ! -f /jffs/scripts/nat-start ]; then
	cat > /jffs/scripts/nat-start <<-EOF
		#!/bin/sh
		dbus fire onnatstart
		
		EOF
	fi
	writenat=$(cat /jffs/scripts/nat-start | grep "nat-start")
	if [ -z "$writenat" ];then
		echo_date 添加nat-start触发事件...用于ss的nat规则重启后或网络恢复后的加载.
		sed -i "2a sleep $ss_basic_sleep" /jffs/scripts/nat-start
		sed -i '3a sh /koolshare/ss/game/nat-start' /jffs/scripts/nat-start
		chmod +x /jffs/scripts/nat-start
	fi
}

#--------------------------------------------------------------------------------------
wan_auto_start(){
	# Add service to auto start
	if [ ! -f /jffs/scripts/wan-start ]; then
		cat > /jffs/scripts/wan-start <<-EOF
			#!/bin/sh
			dbus fire onwanstart
			
			EOF
	fi
	startss=$(cat /jffs/scripts/wan-start | grep "/koolshare/scripts/ss_config.sh")
	if [ -z "$startss" ];then
		echo_date 添加wan-start触发事件...用于ss的各种程序的开机启动，启动延迟$ss_basic_sleep
		sed -i "2a sleep $ss_basic_sleep" /jffs/scripts/wan-start
		sed -i '3a sh /koolshare/scripts/ss_config.sh' /jffs/scripts/wan-start
	fi
	chmod +x /jffs/scripts/wan-start
}

write_cron_job(){
	if [ "1" == "$ss_basic_rule_update" ]; then
		echo_date 添加ss规则定时更新任务，每天"$ss_basic_rule_update_time"自动检测更新规则.
		cru a ssupdate "0 $ss_basic_rule_update_time * * * /bin/sh /koolshare/scripts/ss_rule_update.sh"
	else
		echo_date ss规则定时更新任务未启用！
	fi
}

kill_cron_job(){
	jobexist=`cru l|grep ssupdate`
	# kill crontab job
	if [ ! -z "$jobexist" ];then
		echo_date 删除ss规则定时更新任务.
		sed -i '/ssupdate/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	fi
}


start_dns(){
	# Start dnscrypt-proxy
	if [ "1" == "$ss_game_dns_foreign" ];then
		echo_date 开启 dnscrypt-proxy，你选择了"$ss_game_opendns"节点.
		dnscrypt-proxy --local-address=127.0.0.1:1053 --daemonize -L /koolshare/ss/dnscrypt-resolvers.csv -R $ss_game_opendns  >/dev/null 2>&1
	fi
	
	# Start ss-tunnel
	[ "$ss_game_sstunnel" == "1" ] && gs="208.67.220.220:53"
	[ "$ss_game_sstunnel" == "2" ] && gs="8.8.8.8:53"
	[ "$ss_game_sstunnel" == "3" ] && gs="8.8.4.4:53"
	[ "$ss_game_sstunnel" == "4" ] && gs="$ss_game_sstunnel_user"
	if [ "2" == "$ss_game_dns_foreign" ];then
		
		if [ "$ss_basic_use_rss" == "1" ];then
			echo_date 开启ssr-tunnel...
			rss-tunnel -b 0.0.0.0 -c $CONFIG_FILE -l 1053 -L "$gs" -u -f /var/run/sstunnel.pid >/dev/null 2>&1
		elif  [ "$ss_basic_use_rss" == "0" ];then
			echo_date 开启ss-tunnel...
			ss-tunnel -b 0.0.0.0 -c $CONFIG_FILE -l 1053 -L "$gs" $ARG_OTA $ARG_OBFS -u -f /var/run/sstunnel.pid >/dev/null 2>&1
		fi
	fi

	# Start chinadns
	[ "$ss_game_chinadns_china" == "1" ] && gcc="223.5.5.5"
	[ "$ss_game_chinadns_china" == "2" ] && gcc="223.6.6.6"
	[ "$ss_game_chinadns_china" == "3" ] && gcc="114.114.114.114"
	[ "$ss_game_chinadns_china" == "4" ] && gcc="$ss_game_chinadns_china_user"
	[ "$ss_game_chinadns_china" == "5" ] && gcc="180.76.76.76"
	[ "$ss_game_chinadns_china" == "6" ] && gcc="1.2.4.8"
	[ "$ss_game_chinadns_china" == "7" ] && gcc="119.29.29.29"
	[ "$ss_game_chinadns_foreign" == "1" ] && cdf="208.67.220.220:53"
	[ "$ss_game_chinadns_foreign" == "2" ] && cdf="8.8.8.8:53"
	[ "$ss_game_chinadns_foreign" == "3" ] && cdf="8.8.4.4:53"
	[ "$ss_game_chinadns_foreign" == "4" ] && cdf="$ss_game_chinadns_foreign_user"
	if [ "3" == "$ss_game_dns_foreign" ];then
		if [ "$ss_basic_use_rss" == "1" ];then
			echo_date 开启chinadns，上游国内dns："$gcc"，国外dns：ssr-tunnel...
			rss-tunnel -b 127.0.0.1 -c $CONFIG_FILE -l 1055 -L "$cdf" -u -f /var/run/sstunnel.pid
		elif  [ "$ss_basic_use_rss" == "0" ];then
			echo_date 开启chinadns，上游国内dns："$gcc"，国外dns：ss-tunnel...
			ss-tunnel -b 0.0.0.0 -c $CONFIG_FILE -l 1055 -L "$gs" $ARG_OTA $ARG_OBFS -u -f /var/run/sstunnel.pid >/dev/null 2>&1
		fi
		chinadns -p 1053 -s "$gcc",127.0.0.1:1055 -m -d -c /koolshare/ss/redchn/chnroute.txt &
	fi
	
	# Start DNS2SOCKS
	if [ "4" == "$ss_game_dns_foreign" ]; then
		echo_date 开启dns2socks，监听端口：23456
		if [ "$ss_basic_use_rss" == "1" ];then
			rss-local -b 0.0.0.0 -l 23456 -c $CONFIG_FILE -u -f /var/run/sslocal1.pid >/dev/null 2>&1
		elif  [ "$ss_basic_use_rss" == "0" ];then
			ss-local -b 0.0.0.0 -l 23456 -c $CONFIG_FILE $ARG_OTA $ARG_OBFS -u -f /var/run/sslocal1.pid >/dev/null 2>&1
		fi
		dns2socks 127.0.0.1:23456 "$ss_game_dns2socks_user" 127.0.0.1:1053 > /dev/null 2>&1 &
	fi

	# Start Pcap_DNSProxy
	if [ "5" == "$ss_game_dns_foreign" ]; then
			echo_date 开启Pcap_DNSProxy..
			sed -i '/^Listen Port/c Listen Port = 1053' /koolshare/ss/dns/Config.ini
	      		#sed -i '/^Local Main/c Local Main = 0' /koolshare/ss/dns/Config.conf
			sh /koolshare/ss/dns/dns.sh > /dev/null 2>&1 &
	fi

	# Start pdnsd
	if [ "6" == "$ss_game_dns_foreign"  ]; then
		echo_date 开启 pdnsd，pdnsd进程可能会不稳定，请自己斟酌.
		echo_date 创建/koolshare/ss/pdnsd文件夹.
		mkdir -p /koolshare/ss/pdnsd
		if [ "$ss_game_pdnsd_method" == "1" ];then
			echo_date 创建pdnsd配置文件到/koolshare/ss/pdnsd/pdnsd.conf
			echo_date 你选择了-仅udp查询-，需要开启上游dns服务，以防止dns污染.
			cat > /koolshare/ss/pdnsd/pdnsd.conf <<-EOF
				global {
					perm_cache=2048;
					cache_dir="/koolshare/ss/pdnsd/";
					run_as="nobody";
					server_port = 1053;
					server_ip = 127.0.0.1;
					status_ctl = on;
					query_method=udp_only;
					min_ttl=$ss_game_pdnsd_server_cache_min;
					max_ttl=$ss_game_pdnsd_server_cache_max;
					timeout=10;
				}
				
				server {
					label= "RT-AC68U"; 
					ip = 127.0.0.1;
					port = 1099;
					root_server = on;   
					uptest = none;    
				}
				EOF
			if [ "$ss_game_pdnsd_udp_server" == "1" ];then
				echo_date 开启dns2socks作为pdnsd的上游服务器.
				if [ "$ss_basic_use_rss" == "1" ];then
					rss-local -b 0.0.0.0 -l 23456 -c $CONFIG_FILE -u -f /var/run/sslocal1.pid >/dev/null 2>&1
				elif  [ "$ss_basic_use_rss" == "0" ];then
					ss-local -b 0.0.0.0 -l 23456 -c $CONFIG_FILE $ARG_OTA $ARG_OBFS -u -f /var/run/sslocal1.pid >/dev/null 2>&1
				fi
				dns2socks 127.0.0.1:23456 "$ss_game_pdnsd_udp_server_dns2socks" 127.0.0.1:1099 > /dev/null 2>&1 &
			elif [ "$ss_game_pdnsd_udp_server" == "2" ];then
				echo_date 开启dnscrypt-proxy作为pdnsd的上游服务器.
				dnscrypt-proxy --local-address=127.0.0.1:1099 --daemonize -L /koolshare/ss/dnscrypt-resolvers.csv -R $ss_game_pdnsd_udp_server_dnscrypt  >/dev/null 2>&1
			elif [ "$ss_game_pdnsd_udp_server" == "3" ];then
				[ "$ss_game_pdnsd_udp_server_ss_tunnel" == "1" ] && dns1="208.67.220.220:53"
				[ "$ss_game_pdnsd_udp_server_ss_tunnel" == "2" ] && dns1="8.8.8.8:53"
				[ "$ss_game_pdnsd_udp_server_ss_tunnel" == "3" ] && dns1="8.8.4.4:53"
				[ "$ss_game_pdnsd_udp_server_ss_tunnel" == "4" ] && dns1="$ss_game_pdnsd_udp_server_ss_tunnel_user"
				if [ "$ss_basic_use_rss" == "1" ];then
					echo_date 开启ssr-tunnel作为pdnsd的上游服务器.
					rss-tunnel -b 0.0.0.0 -c $CONFIG_FILE -l 1099 -L "$dns1" -u -f /var/run/sstunnel.pid
				elif  [ "$ss_basic_use_rss" == "0" ];then
					echo_date 开启ss-tunnel作为pdnsd的上游服务器.
					ss-tunnel -b 0.0.0.0 -c $CONFIG_FILE -l 1099 -L "$gs" $ARG_OTA $ARG_OBFS -u -f /var/run/sstunnel.pid >/dev/null 2>&1
				fi
			fi
		elif [ "$ss_game_pdnsd_method" == "2" ];then
			echo_date 创建pdnsd配置文件到/koolshare/ss/pdnsd/pdnsd.conf
			echo_date 你选择了-仅tcp查询-，使用"$ss_game_pdnsd_server_ip":"$ss_game_pdnsd_server_port"进行tcp查询.
			cat > /koolshare/ss/pdnsd/pdnsd.conf <<-EOF
				global {
					perm_cache=2048;
					cache_dir="/koolshare/ss/pdnsd/";
					run_as="nobody";
					server_port = 1053;
					server_ip = 127.0.0.1;
					status_ctl = on;
					query_method=tcp_only;
					min_ttl=$ss_game_pdnsd_server_cache_min;
					max_ttl=$ss_game_pdnsd_server_cache_max;
					timeout=10;
				}
				
				server {
					label= "RT-AC68U"; 
					ip = $ss_game_pdnsd_server_ip;
					port = $ss_game_pdnsd_server_port;
					root_server = on;   
					uptest = none;    
				}
				EOF
			
		fi

		chmod 644 /koolshare/ss/pdnsd/pdnsd.conf
		CACHEDIR=/koolshare/ss/pdnsd
		CACHE=/koolshare/ss/pdnsd/pdnsd.cache
		USER=nobody
		GROUP=nogroup

		if ! test -f "$CACHE"; then
			echo_date 创建pdnsd缓存文件.
			dd if=/dev/zero of=/koolshare/ss/pdnsd/pdnsd.cache bs=1 count=4 2> /dev/null
			chown -R $USER.$GROUP $CACHEDIR 2> /dev/null
		fi
		
		echo_date 启动pdnsd进程...
		pdnsd --daemon -c /koolshare/ss/pdnsd/pdnsd.conf -p /var/run/pdnsd.pid
	fi
}
stop_dns(){
	dnscrypt=$(ps | grep "dnscrypt-proxy" | grep -v "grep")
	pdnsd=$(ps | grep "pdnsd" | grep -v "grep")
	chinadns=$(ps | grep "chinadns" | grep -v "grep")
	DNS2SOCK=$(ps | grep "dns2socks" | grep -v "grep")
	Pcap_DNSProxy=$(ps | grep "Pcap_DNSProxy" | grep -v "grep")
	sstunnel=$(ps | grep "ss-tunnel" | grep -v "grep" | grep -vw "rss-tunnel")
	rsstunnel=$(ps | grep "rss-tunnel" | grep -v "grep" | grep -vw "ss-tunnel")
	
	# kill dnscrypt-proxy
	if [ ! -z "$dnscrypt" ]; then 
		echo_date 关闭dnscrypt-proxy进程...
		killall dnscrypt-proxy
	fi

	# kill ss-tunnel
	if [ ! -z "$sstunnel" ]; then 
		echo_date 关闭ss-tunnel进程...
		killall ss-tunnel >/dev/null 2>&1
	fi
	
	if [ ! -z "$rsstunnel" ]; then 
		echo_date 关闭rss-tunnel进程...
		killall rss-tunnel >/dev/null 2>&1
	fi

	# kill pdnsd
	if [ ! -z "$pdnsd" ]; then 
		echo_date 关闭pdnsd进程...
		killall pdnsd
	fi
	
	# kill Pcap_DNSProxy
	if [ ! -z "$Pcap_DNSProxy" ]; then 
		echo_date 关闭Pcap_DNSProxy进程...
		killall dns.sh >/dev/null 2>&1
		killall Pcap_DNSProxy >/dev/null 2>&1
	fi

	# kill chinadns
	if [ ! -z "$chinadns" ]; then 
		echo_date 关闭chinadns进程...
		killall chinadns
	fi
	
	# kill dns2socks
	if [ ! -z "$DNS2SOCK" ]; then 
		echo_date 关闭dns2socks进程...
		killall dns2socks
	fi

}

delete_conf_files(){
	rm -rf /jffs/configs/dnsmasq.conf.add
}

start_ss_redir(){
	# Start ss-redir
	if [ "$ss_basic_use_rss" == "1" ];then
		echo_date 开启ssr-redir进程，用于透明代理.
		rss-redir -b 0.0.0.0 -u -c $CONFIG_FILE -f /var/run/shadowsocks.pid >/dev/null 2>&1
	elif  [ "$ss_basic_use_rss" == "0" ];then
		echo_date 开启ss-redir进程，用于透明代理.
		ss-redir -b 0.0.0.0 -c $CONFIG_FILE $ARG_OTA $ARG_OBFS -u -f /var/run/shadowsocks.pid >/dev/null 2>&1
	fi
}
	
load_nat(){
	nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers|grep -v PREROUTING|grep -v destination)
	i=120
	until [ -n "$nat_ready" ]
	do
	    i=$(($i-1))
	    if [ "$i" -lt 1 ];then
	        echo_date "Could not load nat rules!"
	        sh /koolshare/ss/stop.sh
	        exit
	    fi
	    sleep 2
	done
	echo_date "加载nat规则!"
	sh /koolshare/ss/game/nat-start start_all
}

restart_dnsmasq(){
	# Restart dnsmasq
	echo_date 重启dnsmasq服务...
	/sbin/service restart_dnsmasq >/dev/null 2>&1
}

remove_status(){
	nvram set ss_foreign_state=""
	nvram set ss_china_state=""
}

main_portal(){
	if [ "$ss_main_portal" == "1" ];then
		nvram set enable_ss=1
		nvram commit
	else
		nvram set enable_ss=0
		nvram commit
	fi
}

detect_qos(){
	echo_date 检测是否符合游戏模式启动条件...
	QOSO=`iptables -t mangle -S | grep -c QOSO`
	if [ "$QOSO" -gt "1" ];then
		echo_date !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		echo_date !!!发现你开启了 Adaptive Qos - 传统带宽管理,该Qos模式和游戏模式冲突!!!
		echo_date !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		echo_date 如果你仍然希望在游戏模式下使用Qos，可以使用Adaptive QoS网络监控家模式，
		echo_date 但是该模式下走ss的流量不会有Qos效果！
		echo_date 退出应用游戏模式，关闭ss！请等待10秒！
		dbus set ss_basic_enable=0
		sleep 10
		exit
	else
		echo_date 未检测到系统设置冲突，符合启动条件！
	fi
}

load_module(){
	xt=`lsmod | grep xt_set`
	OS=$(uname -r)
	if [ -f /lib/modules/${OS}/kernel/net/netfilter/xt_set.ko ] && [ -z "$xt" ];then
		echo_date "加载xt_set.ko内核模块！"
		insmod /lib/modules/${OS}/kernel/net/netfilter/xt_set.ko
	fi
}

case $1 in
start_all)
	#ss_basic_action=1 应用所有设置
	echo_date --------------------- 梅林固件 shadowsocks 游戏模式 -----------------------
	detect_qos
	resolv_server_ip
	creat_ss_json
	creat_dnsmasq_basic_conf
	custom_dnsmasq
	ln_conf
	nat_auto_start
	wan_auto_start
	write_cron_job
	start_dns
	start_ss_redir
	load_module
	load_nat
	restart_dnsmasq
	remove_status
	nvram set ss_mode=3
	nvram commit
	echo_date ---------------------- shadowsocks 游戏模式启动完毕 -----------------------
	;;
restart_dns)
	#ss_basic_action=2 应用DNS设置
	echo_date ------------------------- 游戏模式-重启dns服务 ----------------------------
	creat_ss_json
	detect_qos
	stop_dns
	start_dns
	creat_dnsmasq_basic_conf
	custom_dnsmasq
	ln_conf
	restart_dnsmasq
	remove_status
	echo_date ------------------------ 游戏模式-dns服务重启完毕 --------------------------
	;;
restart_addon)
	#ss_basic_action=4 应用黑白名单设置
	echo_date ------------------------- 游戏模式-重启附加功能 ----------------------------
	detect_qos
	# for sleep walue in start up files
	old_sleep=`cat /jffs/scripts/nat-start | grep sleep | awk '{print $2}'`
	new_sleep="$ss_basic_sleep"
	if [ "$old_sleep" = "$new_sleep" ];then
		echo_date boot delay time not changing, still "$ss_basic_sleep" seconds
	else
		echo_date set boot delay to "$ss_basic_sleep" seconds before starting kcptun service
		# delete boot delay in nat-start and wan-start
		sed -i '/koolshare/d' /jffs/scripts/nat-start >/dev/null 2>&1
		sed -i '/sleep/d' /jffs/scripts/nat-start >/dev/null 2>&1
		sed -i '/koolshare/d' /jffs/scripts/wan-start >/dev/null 2>&1
		sed -i '/sleep/d' /jffs/scripts/wan-start >/dev/null 2>&1
		# re add delay in nat-start and wan-start
		nat_auto_start >/dev/null 2>&1
		wan_auto_start >/dev/null 2>&1
	fi
	
	# for chromecast surpport
	# also for chromecast
	sh /koolshare/ss/game/nat-start start_part_for_addon
	
	# for list update
	kill_cron_job
	write_cron_job
	#remove_status
	remove_status
	main_portal
	
	if [ "$ss_basic_dnslookup" == "1" ];then
		echo_date 设置使用nslookup方式解析SS服务器的ip地址.
	else
		echo_date 设置使用resolveip方式解析SS服务器的ip地址.
	fi

	echo_date ----------------------- 游戏模式-附加功能重启完毕！ ------------------------
	;;
*)
	echo "Usage: $0 (start_all|restart_dns|restart_addon)"
	exit 1
	;;
esac


