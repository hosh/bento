#!/bin/bash

# var to determine package source
PKGSRC=cd

date > /etc/vagrant_box_build_time
loadkeys us

# launch automated install
#su -c 'aif -p automatic -c aif.cfg'

# Since AIF is no longer maintained, we have to do things the hard way:
# AIF uses sfdisk and parses a partition screen. It translates to:

sfdisk -D /dev/sda -uM <<EOF
,100,,*
,512,S
,;,,
EOF

# Translation:
# /dev/sda1 - 100 MiB ext2 boot partition, set as a Linux partition (83)
# /dev/sda2 - 512 MiB swap partition (marked type 84)
# /dev/sda3 - Rest of the harddrive, set as a Linux partition (83)
# See: http://linux.die.net/man/8/sfdisk "Input Format"

mkfs.ext2 /dev/sda1 -L /boot
mkswap /dev/sda2
swapon /dev/sda2
mkfs.ext3 /dev/sda3 -L /

# Mount the newly created disks
mkdir -p /mnt
mount /dev/sda3 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot

# Bootstrap packages
pacstrap /mnt base base-devel

# Install Arch Linux bootloader
arch-chroot /mnt pacman -S --noconfirm grub-bios

# Generate fstab
genfstab -p /mnt >> /mnt/etc/fstab

# copy over the vbox version file
/bin/cp -f /root/.vbox_version /mnt/root/.vbox_version

# chroot into the new system
# Start The World:
mount -o bind /dev /mnt/dev
mount -o bind /sys /mnt/sys
mount -t proc none /mnt/proc
chroot /mnt <<ENDCHROOT

# make sure network is up and a nameserver is available
dhcpcd eth0

# sudo setup
# note: do not use tabs here, it autocompletes and borks the sudoers file
cat <<EOF > /etc/sudoers
root    ALL=(ALL)    ALL
%wheel    ALL=(ALL)    NOPASSWD: ALL
EOF

# set up user accounts
passwd<<EOF
vagrant
vagrant
EOF
useradd -m -G wheel -r vagrant
passwd -d vagrant
passwd vagrant<<EOF
vagrant
vagrant
EOF

# create puppet group
groupadd puppet

# make sure ssh is allowed
echo "sshd:	ALL" > /etc/hosts.allow

# and everything else isn't
echo "ALL:	ALL" > /etc/hosts.deny

# make sure sshd starts
sed -i 's:^DAEMONS\(.*\))$:DAEMONS\1 sshd):' /etc/rc.conf

# install mitchellh's ssh key
mkdir /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' -O /home/vagrant/.ssh/authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh

# choose a mirror
sed -i 's/^#\(.*leaseweb.*\)/\1/' /etc/pacman.d/mirrorlist

# update pacman
[[ $PKGSRC == 'cd' ]] && pacman -Syy
[[ $PKGSRC == 'cd' ]] && pacman -S --noconfirm pacman

# upgrade pacman db
pacman-db-upgrade
pacman -Syy

# install some packages
pacman -S --noconfirm glibc git pkg-config fakeroot
gem install --no-ri --no-rdoc chef facter
cd /tmp
git clone https://github.com/puppetlabs/puppet.git
cd puppet
ruby install.rb --bindir=/usr/bin --sbindir=/sbin

# set up networking
[[ $PKGSRC == 'net' ]] && sed -i 's/^\(interface=*\)/\1eth0/' /etc/rc.conf

# leave the chroot
ENDCHROOT

# take down network to prevent next postinstall.sh from starting too soon
/etc/rc.d/network stop

# and reboot!
reboot
