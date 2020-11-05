#### Configure your setting ####
read -p "VPN_DNS1": VPN_DNS1
read -p "VPN_DNS2": VPN_DNS2
read -p "IPSEC_PSK": IPSEC_PSK
VPN_NETWORK_INTERFACE=`ip -4 route | awk 'NR==1 {print $5}'`


#### Prepare tools ####
yum -y install vim lrzsz bash-completion net-tools wget gcc make epel-release
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
#plugin /usr/lib/pppd/2.4.7/radius.so
#plugin /usr/lib/pppd/2.4.7/radattr.so
#radius-config-file /usr/local/etc/radiusclient/radiusclient.conf
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
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-port=1701/udp
#firewall-cmd --permanent --add-port=1723/tcp
#firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -i $VPN_NETWORK_INTERFACE -p gre -j ACCEPT
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

#### Open server ####
systemctl start xl2tpd ipsec && systemctl enable xl2tpd ipsec
sysctl -p
reboot
