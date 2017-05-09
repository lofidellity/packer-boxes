#!/bin/bash -eux

yum -y remove bison
yum -y remove flex
yum -y remove gcc
yum -y remove gcc-c++
yum -y remove kernel-devel
yum -y remove kernel-headers
yum -y remove cloog-ppl
yum -y remove cpp
yum -y remove libmpc
yum -y clean all

echo "==> Ensuring there is no 'requiretty' in sudoers"

sed -i 's/\(Defaults.*requiretty\)/# \1/g' /etc/sudoers

echo "==> Cleaning up temporary network addresses"

sed -i '/HOSTNAME/d' /etc/sysconfig/network
rm -f /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
rm -rf /dev/.udev/


for ndev in `ls -1 /etc/sysconfig/network-scripts/ifcfg-*`; do
    if [ "`basename $ndev`" != "ifcfg-lo" ]; then
        sed -i '/^HWADDR/d' "$ndev";
        sed -i '/^UUID/d' "$ndev";
    fi
done

DISK_USAGE_BEFORE_CLEANUP=$(df -h)

echo "==> Remove packages needed for building guest tools"
yum -y remove gcc cpp libmpc mpfr kernel-devel kernel-headers perl

echo "==> Clean up yum cache of metadata and packages to save space"
yum -y --enablerepo='*' clean all
find /var/cache/yum/ -type f -exec rm -f {} \;

echo "==> Clear core files"
rm -f /core*

echo "==> Removing temporary files used to build box"
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /root
cp -R /etc/skel /root
chown root:root /root
chmod 700 /root

echo "==> Remove ssh server keys"
rm -rf /etc/ssh/*_host_*

echo "==> Remove the PAM data"
rm -rf /var/run/console/*
rm -rf /var/run/faillock/*
rm -rf /var/run/sepermit/*

echo "==> Remove the crash data generated by ABRT"
rm -rf /var/spool/abrt/*

echo "==> Remove email from the local mail spool directory"
rm -rf /var/spool/mail/*
rm -rf /var/mail/*

echo "==> Remove the local machine ID"
if [ -f /etc/machine-id ]; then
    rm -f /etc/machine-id
    touch /etc/machine-id
fi
if [ -f /var/lib/dbus/machine-id ]; then
    rm -f /var/lib/dbus/machine-id
    touch /var/lib/dbus/machine-id
fi

echo "==> Empty log files"
find /var/log -type f | while read f; do echo -ne '' > "$f"; done;

echo "==> Cleaning up leftover dhcp leases"
rm -f /var/lib/dhclient/*

echo "==> Remove resolv.conf"
> /etc/resolv.conf

echo "==> Remove caches"
find /var/cache -type f -exec rm -rf {} \;

echo "==> Clean up after cloud-init"
rm -rf /var/lib/cloud/sem/* /var/lib/cloud/instance /var/lib/cloud/instances/*

echo "==> Rebuild RPM DB"
rpmdb --rebuilddb
rm -f /var/lib/rpm/__db*

echo '==> Clear out swap and disable until reboot'
set +e
swapuuid=$(/sbin/blkid -o value -l -s UUID -t TYPE=swap)
case "$?" in
	2|0) ;;
	*) exit 1 ;;
esac
set -e
if [ "x${swapuuid}" != "x" ]; then
    # Whiteout the swap partition to reduce box size
    # Swap is disabled till reboot
    swappart=$(readlink -f /dev/disk/by-uuid/$swapuuid)
    /sbin/swapoff "${swappart}"
    dd if=/dev/zero of="${swappart}" bs=1M || echo "dd exit code $? is suppressed"
    /sbin/mkswap -U "${swapuuid}" "${swappart}"
fi

echo '==> Zeroing out empty area to save space in the final image'
# Zero out the free space to save space in the final image.  Contiguous
# zeroed space compresses down to nothing.
dd if=/dev/zero of=/EMPTY bs=1M || echo "dd exit code $? is suppressed"
rm -f /EMPTY

# Block until the empty file has been removed, otherwise, Packer
# will try to kill the box while the disk is still full and that's bad
sync

echo "==> Disk usage before cleanup"
echo ${DISK_USAGE_BEFORE_CLEANUP}

echo "==> Disk usage after cleanup"
df -h
