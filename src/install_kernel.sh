#!/bin/bash

# This script is designed to be run in a chroot environment
# as the final step in the installation process.
#
# - Install (appropriate) kernel package
# - Reflash uboot if it is missing
# - Set up correct uboot script, with correct rootdevice= parameter

KEXT="-gk802-desktop"
UBOOT_CONSOLE=""
SCRIPT_SUFFIX=""
if grep -q ttymxc3 /proc/cmdline; then
    KEXT="-gk802-headless"
    UBOOT_CONSOLE='console=ttymxc3,115200'
    SCRIPT_SUFFIX=" (headless)"
fi

export DEBIAN_FRONTEND=noninteractive
/usr/bin/apt-get install -q -y initramfs-tools uboot-mkimage
# for some reason man-db seems to fail at this point, rerun it...
/usr/bin/dpkg --configure -a

cd /gk802_components
/usr/bin/dpkg --install linux-image*${KEXT}*.deb

# Set up boot arguments, ubootcmd
ROOTDEV=`/bin/grep -v '^#' /etc/fstab | /bin/grep ' / ' | /usr/bin/cut -d' ' -f1`

sed s/@ROOTDEV@/${ROOTDEV}/ ubootcmd.src \
    | sed s/@CONSOLE@/${UBOOT_CONSOLE}/ \
    > ubootcmd.src.out

/usr/bin/mkimage -T script -C none -n "Debian GK802 boot${SCRIPT_SUFFIX}" -d ubootcmd.src.out /boot/ubootcmd

cd /boot
ln -s vmlinuz* zImage
ln -s vmlinuz* zImage_recovery
ln -s initrd.img* initrd
ln -s initrd.img* initrd_recovery

# Check if uboot was rewritten on mmc 0 during install
CHECK_ZEROES=`dd if=/dev/mmcblk0 bs=1k skip=1 count=1 | md5sum | cut -d' ' -f1`
ALL_ZEROES="0f343b0931126a20f133d67c2b018a3b"

if [ "$CHECK_ZEROES" = "$ALL_ZEROES" ]; then
    cd /gk802_components
    dd if=u-boot.imx of=/dev/mmcblk0 bs=1k seek=1
fi

# Add ttymxc3 to inittab so we get a tty there
echo "T0:23:respawn:/sbin/getty -L ttymxc3 115200 vt100" >> /etc/inittab
