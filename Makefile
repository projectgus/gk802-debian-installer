.PHONY : clean all 

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-

PMAKE=make -j4
# kernel git revision
KERNELREV := $(shell cd kernel; git rev-parse --verify --short HEAD)
# kernel version, ie 3.x.x - usually KERNELREV and KERNELVER are taken together as the revision string, but that is config-dependent...
KERNELVER := $(shell cd kernel; make kernelversion)
# Debian kernel revision, increment the final number to add a new revision (this may be a bad way to do this!)
DEBIAN_REVISION := 1

# $(1) argument is either 'desktop' or 'headless'
DEB = linux-image-$(KERNELVER)-$(KERNELREV)-gk802_$(KERNELVER).$(DEBIAN_REVISION)_armhf.deb
APPEND_TO_VERSION = "-$(KERNELREV)-gk802"
VMLINUZ = vmlinuz-$(KERNELVER)-$(KERNELREV)-gk802

# Internal environment variables
IMG=gk802_debian_installer.img

MAKE_KPKG=CONCURRENCY_LEVEL=4 DEB_HOST_ARCH=armhf fakeroot make-kpkg --arch arm --subarch gk802 --initrd --cross-compile arm-linux-gnueabihf- --revision $(KERNELVER).$(DEBIAN_REVISION)

all: $(IMG)

clean:
	rm -rf build/* $(IMG) *.deb
	make -C uboot clean
	make -C kernel clean

$(IMG): build/partition.img uboot/u-boot.imx
	dd if=build/partition.img of=$(IMG) bs=512 seek=2048
	sfdisk --force $(IMG) < src/sfdisk_partition.txt
	dd if=uboot/u-boot.imx of=$(IMG) bs=1k seek=1 conv=notrunc

# Uboot build process

uboot/u-boot.imx: uboot/include/config.h
	$(PMAKE) -C uboot/

uboot/include/config.h:
	make -C uboot gk802_config
	cat src/uboot_extraconfig.h >> uboot/include/config.h

# Kernel package build processes

$(DEB): src/config-server
	cp src/config-server kernel/.config
	cd kernel && make oldconfig
	cd kernel && $(MAKE_KPKG) --append-to-version $(APPEND_TO_VERSION) kernel_image


# Partition image for the installer disk image
#
# Uses a loopback device, so requires sudo for root access
#
build/partition.img: build/installer_zImage build/uInitRdInstaller src/ubootcmd_installer.src
	dd if=/dev/zero of=build/partition.img bs=512 count=96256
	sudo losetup /dev/loop0 build/partition.img
	sudo mkfs.ext2 /dev/loop0
	mkdir -p build/mount-temp
	sudo mount /dev/loop0 build/mount-temp
	sudo cp build/installer_zImage build/mount-temp/zImage
	sudo cp build/uInitRdInstaller build/mount-temp/
	sudo mkimage -T script -C none -n "GK802 Debian installer" -d src/ubootcmd_installer.src build/mount-temp/ubootcmd
	sudo umount build/mount-temp
	sudo losetup -d /dev/loop0

# Extract the installation zImage from the desktop kernel deb
build/installer_zImage: build/kernel_unpacked/boot
	cp build/kernel_unpacked/boot/$(VMLINUZ) build/installer_zImage

build/kernel_unpacked/boot: $(DEB)
	mkdir -p build/kernel_unpacked
	dpkg -x $(DEB) build/kernel_unpacked

# Installer initrd

build/uInitRdInstaller: build/initrd.gz
	mkimage -A arm -O linux -T ramdisk -a 0x11008000 -n "GK802 Debian netinst initrd" -d build/initrd.gz build/uInitRdInstaller

build/initrd.gz: build/installer_root
	cd build/installer_root && find . | fakeroot cpio -H newc -o | gzip -c > ../initrd.gz

# Installer root directory, used as contents of the initrd
build/installer_root: src/vexpress-initrd.gz uboot/u-boot.imx src/finish-install.d/* src/base-installer.d/* $(DEB) src/install_kernel_uboot.sh src/ubootcmd.src build/kernel_unpacked/lib/modules src/preseed.cfg
	mkdir -p $@
	cd $@ && zcat ../../src/vexpress-initrd.gz | fakeroot cpio -id
	rm -rf $@/lib/modules/*
	fakeroot cp -a build/kernel_unpacked/lib/modules/* $@/lib/modules
	mkdir -p $@/gk802_components
	fakeroot cp -a uboot/u-boot.imx $(DEB) src/install_kernel_uboot.sh src/ubootcmd.src $@/gk802_components
	fakeroot cp -a src/finish-install.d/* $@/usr/lib/finish-install.d/
	fakeroot cp -a src/base-installer.d/* $@/usr/lib/base-installer.d/
	fakeroot cp -a src/preseed.cfg $@/
	touch build/installer_root

