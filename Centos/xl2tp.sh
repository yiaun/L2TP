#### Prepare tools ####
yum -y install vim lrzsz bash-completion net-tools wget gcc
sed -i '7s/enforcing/disabled/' /etc/sysconfig/selinux
setenforce 0

#### Synchronization time ####
sed -i '3s/pool/#pool/' /etc/chrony.conf
sed -i '3 a server ntp.aliyun.com iburst' /etc/chrony.conf
systemctl restart chronyd

####
