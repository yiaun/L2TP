#!/bin/bash

#### Configure your setting ####
read -p "VPN_DNS1": VPN_DNS1
read -p "VPN_DNS2": VPN_DNS2
read -p "IPSEC_PSK": IPSEC_PSK
VPN_NETWORK_INTERFACE=`ip -4 route | awk 'NR==1 {print $5}'`

#### update && upgrade ####
apt -y update && apt -y upgrade

#### tzselect CST ####
tzselect << EOF
4
9
1
1
EOF
if [ ! -f /etc/localtime ];then
	rm -rf /etc/localtime
	ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
else
	ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
fi

#### Determine the kernel ####
version=`awk -F'=' 'NR==11{print $2}' /etc/os-release`
if [ $version = bionic ];then
	echo "Congratulations on your continued installation"
else
	break
fi

#### install tools ####
apt -y install net-tools wget unzip lsof lrzsz vim git gcc make 

#### install xl2tpd pptpd libreswan lsof ####
apt -y install xl2tpd pptpd libreswan lsof

#### Create IPsec (Libreswan) config ####

#### /etc/ipsec.conf ####
if [ ! -f "/etc/ipsec.conf.bak" ];then
	mv /etc/ipsec.conf /etc/ipsec.conf.bak
else
	rm -rf /etc/ipsec.conf
fi
cat > /etc/ipsec.conf <<EOF
config setup
	uniqueids=no
	virtual-private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12

conn ikev1
	authby=secret
	pfs=no
	auto=add
	rekey=no
	left=%defaultroute
	right=%any
	ikev2=never
	type=transport
	leftprotoport=17/1701
	rightprotoport=17/%any
	dpddelay=15
	dpdtimeout=30
	dpdaction=clear

conn ikev1-nat
	also=ikev1
	rightsubnet=vhost:%priv
EOF

#### Create xl2tpd config ####

#### /etc/xl2tpd/xl2tpd.conf ####
if [ ! -f "/etc/xl2tpd/xl2tpd.conf.bak" ];then
	mv /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.bak
else
	rm -rf /etc/xl2tpd/xl2tpd.conf
fi
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
[lns default]
ip range = 192.168.42.20-192.168.42.200
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

#### /etc/pptpd.conf ####
if [ ! -f "/etc/pptpd.conf.bak" ];then
	mv /etc/pptpd.conf /etc/pptpd.conf.bak
else
	rm -rf /etc/pptpd.conf
fi
cat > /etc/pptpd.conf << EOF
option /etc/ppp/options.pptpd
logwtmp
localip=192.168.43.1
remoteip=192.168.43.20-200
EOF

#### Set xl2tpd options ####

#### /etc/ppp/options.xl2tpd ####
if [ ! -f "/etc/ppp/options.xl2tpd" ];then
	echo "options.xl2tpd does not exist"
else
	rm -rf /etc/ppp/options.xl2tpd
fi
cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns $VPN_DNS1
ms-dns $VPN_DNS2
noccp
auth
hide-password
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
logfile /var/log/xl2tpd.log
plugin /usr/lib/pppd/2.4.7/radius.so
plugin /usr/lib/pppd/2.4.7/radattr.so
radius-config-file /usr/local/etc/radiusclient/radiusclient.conf
EOF

#### /etc/ppp/options.pptpd ####
if [ ! -f "/etc/ppp/options.pptpd.bak" ];then
	mv /etc/ppp/options.pptpd /etc/ppp/options.pptpd.bak
else
	rm -rf /etc/ppp/options.pptpd
fi
cat > /etc/ppp/options.pptpd << EOF
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns $VPN_DNS1
ms-dns $VPN_DNS2
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd
logfile /var/log/pptpd.log
plugin /usr/lib/pppd/2.4.7/radius.so
plugin /usr/lib/pppd/2.4.7/radattr.so
radius-config-file /usr/local/etc/radiusclient/radiusclient.conf
EOF


#### Specify IPsec PSK ####
PUBLIC_IP=`curl ip.sb`
#### /etc/ipsec.d/ipsec.secrets ####

if [ ! -f "/etc/ipsec.secrets" ];then
	echo "ipsec.secrets does not exist"
else
	rm -rf /etc/ipsec.secrets
fi
cat > /etc/ipsec.secrets << EOF
$PUBLIC_IP %any : PSK "$IPSEC_PSK"
EOF

#### Update sysctl settings ####

#### /etc/sysctl.conf ####
if [ ! -f "/etc/sysctl.conf.bak" ];then
	mv /etc/sysctl.conf /etc/sysctl.conf.bak
else
	rm -rf /etc/sysctl.conf
fi
cat > /etc/sysctl.conf << EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.$VPN_NETWORK_INTERFACE.rp_filter = 0
net.ipv4.conf.$VPN_NETWORK_INTERFACE.send_redirects = 0
net.ipv4.conf.$VPN_NETWORK_INTERFACE.accept_redirects = 0
net.ipv4.conf.ip_vti0.rp_filter = 0
net.ipv4.conf.ip_vti0.send_redirects = 0
net.ipv4.conf.ip_vti0.accept_redirects = 0
net.ipv4.conf.lo.rp_filter = 0
net.ipv4.conf.lo.send_redirects = 0
net.ipv4.conf.lo.accept_redirects = 0
EOF

#### open UFW ####
sysctl -p 
systemctl disable ufw
systemctl stop ufw
apt -y install firewalld
systemctl enable firewalld
firewall-cmd --permanent --add-masquerade
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-port=1723/tcp
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -i $VPN_NETWORK_INTERFACE -p gre -j ACCEPT
firewall-cmd --reload

#### install Freeradius ####
apt -y install freeradius freeradius-utils freeradius-mysql
cd ~
wget https://github.com/aryayk/L2TP/releases/download/freeradius/freeradius-client-1.1.7.tar.gz
tar -zxvf freeradius-client-1.1.7.tar.gz
cd freeradius-client-1.1.7
./configure
make && make install

#### install mysql ####
apt -y install mysql-server libmysql++-dev
systemctl restart mysqld
mysql -e "create database radius;"
mysql -e "create user 'radius'@'localhost' identified by 'radpass';"
mysql -e "alter user 'radius'@'localhost' identified with mysql_native_password by 'radpass';"
mysql -e "grant all privileges on radius.* to 'radius'@'localhost';"
mysql -e "flush privileges;"
mysql -uradius -pradpass -Dradius </etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql

#### Configure freeradius ####

#### /etc/freeradius/3.0/mods-available/sql ####
if [ ! -f "/etc/freeradius/3.0/mods-available/sql.bak" ];then
	cp -arp /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-available/sql.bak
else
	rm -rf /etc/freeradius/3.0/mods-available/sql
	cp -arp /etc/freeradius/3.0/mods-available/sql.bak /etc/freeradius/3.0/mods-available/sql
fi
sed -i '31s/null/mysql/' /etc/freeradius/3.0/mods-available/sql
sed -i '87s/sqlite/mysql/' /etc/freeradius/3.0/mods-available/sql
sed -i '91,94s/.//' /etc/freeradius/3.0/mods-available/sql
sed -i '245s/.//' /etc/freeradius/3.0/mods-available/sql
cd /etc/freeradius/3.0/mods-enabled/
ln -s ../mods-available/sql
chown -Rf root:radiusd /etc/freeradius/3.0/mods-enabled/sql

#### /etc/freeradius/3.0/sites-available/default ####
if [ ! -f "/etc/freeradius/3.0/sites-available/default.bak" ];then
	cp -arp /etc/freeradius/3.0/sites-available/default /etc/freeradius/3.0/sites-available/default.bak
else
	rm -rf /etc/freeradius/3.0/sites-available/default
	cp -arp /etc/freeradius/3.0/sites-available/default.bak /etc/freeradius/3.0/sites-available/default
fi
sed -i '405s/-sql/sql/' /etc/freeradius/3.0/sites-available/default
sed -i '640s/-sql/sql/' /etc/freeradius/3.0/sites-available/default
sed -i '732s/-sql/sql/' /etc/freeradius/3.0/sites-available/default
sed -i '689s/.//' /etc/freeradius/3.0/sites-available/default

#### Configure freeradius-client ####
#### /usr/local/etc/radiusclient/dictionary ####
if [ ! -f "/usr/local/etc/radiusclient/dictionary.bak" ];then
	cp -arp /usr/local/etc/radiusclient/dictionary /usr/local/etc/radiusclient/dictionary.bak
else
	rm -rf /usr/local/etc/radiusclient/dictionary
	cp -arp /usr/local/etc/radiusclient/dictionary.bak /usr/local/etc/radiusclient/dictionary
fi
sed -i '/ipv6/s/^/#/' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.sip' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.ascend' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.merit' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.compat' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.microsoft' /usr/local/etc/radiusclient/dictionary

#### dictionary.microsoft ####
if [ ! -f "/usr/local/etc/radiusclient/dictionary.microsoft" ];then
	wget -P /usr/local/etc/radiusclient/ https://github.com/aryayk/L2TP/releases/download/dictionary/dictionary.microsoft
else
	rm -rf /usr/local/etc/radiusclient/dictionary.microsoft
	wget -P /usr/local/etc/radiusclient/ https://github.com/aryayk/L2TP/releases/download/dictionary/dictionary.microsoft
fi

#### /usr/local/etc/radiusclient/radiusclient.conf ####
if [ ! -f "/usr/local/etc/radiusclient/radiusclient.conf.bak" ];then
	cp -arp /usr/local/etc/radiusclient/radiusclient.conf /usr/local/etc/radiusclient/radiusclient.conf.bak
else
	rm -rf /usr/local/etc/radiusclient/radiusclient.conf
	cp -arp /usr/local/etc/radiusclient/radiusclient.conf.bak /usr/local/etc/radiusclient/radiusclient.conf
fi
sed -i '83s/^/#/g' /usr/local/etc/radiusclient/radiusclient.conf

#### /usr/local/etc/radiusclient/servers ####
if [ ! -f "/usr/local/etc/radiusclient/servers.bak" ];then
	cp -arp /usr/local/etc/radiusclient/servers /usr/local/etc/radiusclient/servers.bak
else
	rm -rf /usr/local/etc/radiusclient/servers
	cp -arp /usr/local/etc/radiusclient/servers.bak /usr/local/etc/radiusclient/servers
fi
sed -i '10s/.//' /usr/local/etc/radiusclient/servers

#### systemcl disable ####
if [ ! -f "/lib/systemd/system/rc-local.service.bak" ];then
	cp -arp /lib/systemd/system/rc-local.service /lib/systemd/system/rc-local.service.bak
else
	rm -rf rc-local.service
	cp -arp /lib/systemd/system/rc-local.service.bak /lib/systemd/system/rc-local.service
fi
sed -i '23a Alias=rc-local.service' /lib/systemd/system/rc-local.service
sed -i '23a WantedBy=multi-user.target' /lib/systemd/system/rc-local.service
sed -i '23a [Install]' /lib/systemd/system/rc-local.service

systemctl disable mysql ipsec xl2tpd pptpd freeradius
if [ ! -f "/root/l2tprestart.sh" ];then
	echo l2tprestart.sh does not exist
else
	rm -rf /root/l2tprestart.sh
fi
cat > /root/l2tprestart.sh << EOF
#!/bin/bash
systemctl restart mysql ipsec xl2tpd pptpd
systemctl restart freeradius
EOF
sed -i "3a /bin/echo \$(\/bin\/date +%F-%T) >> /var/log/l2tprestart.log" /root/l2tprestart.sh
chmod +x /root/l2tprestart.sh
cat > /etc/rc.local <<EOF
#!/bin/bash
/bin/bash /root/l2tprestart.sh
EOF
if [ ! -f "/etc/rc.local.bak" ];then
	cp -arp /etc/rc.local /etc/rc.local.bak
else
	rm -rf /etc/rc.local
	cp -arp /etc/rc.local.bak /etc/rc.local
fi
chmod +x /etc/rc.local
systemctl enable rc-local.service
reboot
