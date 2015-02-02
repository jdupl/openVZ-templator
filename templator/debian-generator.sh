#!/bin/bash
#
# Copyright (C) 2014  Justin Duplessis
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Script to generate a Debian openVZ template.
# v1.1.1
#
# Currently supports custom locale, mirrors, timezone and Debian release.
#
# Have a base Debian openvz template and run this script as root in 
# the hypervisor.
#
# TODO
# move vars to CLI arguments

mirror="http://ftp3.nrc.ca/debian"
debian_version="wheezy"
timezone="America/Montreal"
temp_vm_id="1337"
lang="en_CA"
encoding="UTF-8"
vz_path="/var/lib/vz"
base_template="debian-7.0-standard_7.0-2_i386.tar.gz"
temp_ip="192.168.2.170"
temp_dns="8.8.8.8"

# Check if "basic config" exists in current installation

if [[ ! -f /etc/pve/openvz/ve-basic.conf-sample ]]; then
    cat > /etc/pve/openvz/ve-basic.conf-sample <<EOF
ONBOOT="no"

PHYSPAGES="0:512M"
SWAPPAGES="0:512M"
KMEMSIZE="232M:256M"
DCACHESIZE="116M:128M"
LOCKEDPAGES="256M"
PRIVVMPAGES="unlimited"
SHMPAGES="unlimited"
NUMPROC="unlimited"
VMGUARPAGES="0:unlimited"
OOMGUARPAGES="0:unlimited"
NUMTCPSOCK="unlimited"
NUMFLOCK="unlimited"
NUMPTY="unlimited"
NUMSIGINFO="unlimited"
TCPSNDBUF="unlimited"
TCPRCVBUF="unlimited"
OTHERSOCKBUF="unlimited"
DGRAMRCVBUF="unlimited"
NUMOTHERSOCK="unlimited"
NUMFILE="unlimited"
NUMIPTENT="unlimited"

# Disk quota parameters (in form of softlimit:hardlimit)
DISKSPACE="10G:11G"
DISKINODES="2000000:2200000"
QUOTATIME="0"
QUOTAUGIDLIMIT="0"

CPUUNITS="1000"

EOF
fi

# Create container with base template
vzctl create $temp_vm_id --ostemplate ${vz_path}/template/cache/${base_template} --config basic

# Give basic network access to CT
vzctl set $temp_vm_id --ipadd $temp_ip --save
vzctl set $temp_vm_id --nameserver $temp_dns --save

# Start CT
vzctl start $temp_vm_id

sleep 1s

# Generate new locale.gen file
cat > ${vz_path}/private/${temp_vm_id}/etc/locale.gen <<EOF
# This file lists locales that you wish to have built. You can find a list
# of valid supported locales at /usr/share/i18n/SUPPORTED, and you can add
# user defined locales to /usr/local/share/i18n/SUPPORTED. If you change
# this file, you need to rerun locale-gen.
${lang}.${encoding} ${encoding}
EOF

# Set default locale
cat > ${vz_path}/private/${temp_vm_id}/etc/default/locale <<EOF
LANG="${lang}.${encoding}"
EOF

# Generate new /etc/apt/sources.list file
cat > ${vz_path}/private/${temp_vm_id}/etc/apt/sources.list <<EOF
deb ${mirror} ${debian_version} main contrib
deb ${mirror} ${debian_version}-updates main contrib
deb http://security.debian.org ${debian_version}/updates main contrib
EOF

# Generate new locale
vzctl exec $temp_vm_id locale-gen

vzctl stop $temp_vm_id
sleep 1s
vzctl start $temp_vm_id
sleep 5s

# Update vm with new sources.list
vzctl exec $temp_vm_id apt-get update
vzctl exec $temp_vm_id DEBIAN_FRONTEND=noninteractive apt-get upgrade -o Dpkg::Options::=--force-confnew --yes --force-yes
vzctl exec $temp_vm_id DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -o Dpkg::Options::=--force-confnew --yes --force-yes

# Install some basic utilities
vzctl exec $temp_vm_id apt-get install -y less htop

# Clean apt-get
vzctl exec $temp_vm_id apt-get autoremove -y
vzctl exec $temp_vm_id apt-get clean -y

# Script to regenerate new keys at first boot of the template
cat  > ${vz_path}/private/${temp_vm_id}/etc/init.d/ssh_gen_host_keys << EOF
ssh-keygen -f /etc/ssh/ssh_host_rsa_key -t rsa -N '' 
ssh-keygen -f /etc/ssh/ssh_host_dsa_key -t dsa -N ''
rm -f \$0
EOF

# Make script executable
vzctl exec $temp_vm_id chmod a+x /etc/init.d/ssh_gen_host_keys

# Enable init script
vzctl exec $temp_vm_id insserv /etc/init.d/ssh_gen_host_keys

# Change timezone
vzctl exec $temp_vm_id ln -sf /usr/share/zoneinfo/$timezone /etc/timezone

# Delete CT's hostname file
rm -f ${vz_path}/private/${temp_vm_id}/etc/hostname

# Reset CT's resolv.conf
> ${vz_path}/private/${temp_vm_id}/etc/resolv.conf

# Delete CT ssh keys
rm -f ${vz_path}/private/${temp_vm_id}/etc/ssh/ssh_host_*

# Delete history
vzctl exec $temp_vm_id history -c

# Stop the CT
vzctl stop $temp_vm_id

# Compress the CT to a template
cd ${vz_path}/private/${temp_vm_id}/
tar --numeric-owner -zcf ${vz_path}/template/cache/debian-${debian_version}-i386-${lang}.${encoding}-$(date +%F).tar.gz .

# Cleanup (delete temp container)
vzctl destroy $temp_vm_id
