#!/bin/bash

#### Configure your setting ####
read -p "VPN_DNS1": VPN_DNS1
read -p "VPN_DNS2": VPN_DNS2
read -p "IPSEC_PSK": IPSEC_PSK
VPN_NETWORK_INTERFACE=`ip -4 route | awk 'NR==1 {print $5}'`


#### Prepare tools ####
yum -y install vim lrzsz bash-completion net-tools wget gcc make git epel-release
sed -i '7s/enforcing/disabled/' /etc/sysconfig/selinux
setenforce 0

#### Synchronization time ####
sed -i '3s/pool/#pool/' /etc/chrony.conf
sed -i '3 a server ntp.aliyun.com iburst' /etc/chrony.conf
systemctl restart chronyd

#### Install L2tp ####
yum -y install xl2tpd libreswan lsof 

#### Create IPsec (Libreswan) config ####
mv /etc/ipsec.conf /etc/ipsec.conf.bak
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
mv /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.bak
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

#### Set xl2tpd options ####
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
EOF

#### Specify IPsec PSK ####
cat > /etc/ipsec.d/ipsec.secrets << EOF
 : PSK "$IPSEC_PSK"
EOF

#### Update sysctl settings ####
mv /etc/sysctl.conf /etc/sysctl.conf.bak
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

#### Open firewalld ####
sysctl -p
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload


#### Install mysql ####
yum -y install mysql mysql-server
systemctl start mysqld && systemctl enabled mysqld
mysql -e "create database radius;"
mysql -uroot -p -Dradius </etc/raddb/mods-config/sql/main/mysql/schema.sql
mysql -e "create user 'radius'@'localhost' identified by 'password';"
mysql -e "alter user 'radius'@'localhost' identified with mysql_native_password by 'password';"
mysql -e "grant all privileges on radius.* to 'radius'@'localhost';"
mysql -e "flush privileges;"

#### install Freeradius ####
yum -y install freeradius freeradius-utils freeradius-mysql
cd ~
wget -c ftp://ftp.freeradius.org/pub/freeradius/freeradius-client-1.1.7.tar.gz 
tar -zxvf freeradius-client-1.1.7.tar.gz
cd freeradius-client-1.1.7
./configure
make && make install

#### Configure freeradius ####
cp -arp /etc/raddb/modsavailable/sql /etc/raddb/mods-available/sql.bak
sed -i '31s/null/mysql/' /etc/raddb/mods-available/sql
sed -i '87s/sqlite/mysql/' /etc/raddb/mods-available/sql
sed -i '91,94s/.//' /etc/raddb/mods-available/sql
sed -i '245s/.//' /etc/raddb/mods-available/sql
cd /etc/raddb/mods-enabled/
ln -s ../mods-available/sql
chown -Rf root:radiusd /etc/raddb/mods-enabled/sql

cd /etc/raddb/sites-available/
sed -i '405s/-sql/sql/' /etc/raddb/sites-available/default
sed -i '640s/-sql/sql/' /etc/raddb/sites-available/default
sed -i '732s/-sql/sql/' /etc/raddb/sites-available/default
sed -i '682s/.//' /etc/raddb/sites-available/default


#### Configure freeradius-client ####
sed -i '/ipv6/s/^/#/' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.sip' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.ascend' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.merit' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.compat' /usr/local/etc/radiusclient/dictionary
sed -i '$a INCLUDE /usr/local/etc/radiusclient/dictionary.microsoft' /usr/local/etc/radiusclient/dictionary
sed -i '83s/^/#/g' /usr/local/etc/radiusclient/radiusclient.conf
sed -i '10s/.//' /usr/local/etc/radiusclient/servers

#### add option.xl2tpd ####
sed -i '$a plugin /usr/lib64/pppd/2.4.7/radius.so' /etc/ppp/options.xl2tpd
sed -i '$a plugin /usr/lib64/pppd/2.4.7/radattr.so' /etc/ppp/options.xl2tpd
sed -i '$a radius-config-file /usr/local/etc/radiusdclient/radiusclient.conf' /etc/ppp/options.xl2tpd

####
systemctl start xl2tpd ipsec mysqld && systemctl enable xl2tpd ipsec mysqld
systemctl start radiusd && systemcl enabled radiusd













