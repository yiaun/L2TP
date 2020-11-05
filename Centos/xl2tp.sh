#### Prepare tools ####
yum -y install vim lrzsz bash-completion net-tools wget gcc
sed -i '7s/enforcing/disabled/' /etc/sysconfig/selinux
setenforce 0

#### Synchronization time ####
sed -i '2s/pool/#pool/' /etc/chrony.conf
sed -i '3s/server ntp.aliyun.com iburst'
systemctl restart chronyd
