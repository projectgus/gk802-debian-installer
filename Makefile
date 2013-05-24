.PHONY : clean all zips

export ARCH=arm
export CROSS_COMPILE?=arm-linux-gnueabi-

PMAKE ?= make -j4
# kernel git revision
KERNELREV := $(shell cd kernel; git rev-parse --verify --short HEAD)
# kernel version, ie 3.x.x - usually KERNELREV and KERNELVER are taken together as the revision string, but that is config-dependent...
KERNELVER := $(shell cd kernel; make kernelversion)
# Debian kernel revision, increment the final number to add a new revision (this may be a bad way to do this!)
DEBIAN_REVISION := 2

# $(1) argument is either 'desktop' or 'headless'
APPEND_TO_VERSION = "-$(KERNELREV)-$(DEBIAN_REVISION)-gk802"
DEB = linux-image-$(KERNELVER)$(APPEND_TO_VERSION)_$(KERNELVER).$(DEBIAN_REVISION)_armhf.deb
VMLINUZ = vmlinuz-$(KERNELVER)$(APPEND_TO_VERSION)

# Internal environment variables
IMG=gk802_debian_installer.img
MAKE_KPKG=CONCURRENCY_LEVEL=4 DEB_HOST_ARCH=armhf fakeroot make-kpkg --arch arm --subarch gk802 --initrd --cross-compile arm-linux-gnueabihf- --revision "$(KERNELVER).$(DEBIAN_REVISION)" --append-to-version $(APPEND_TO_VERSION)

all: $(IMG)

zips: $(IMG)
	zip gk802_debian_installer.zip $(IMG)
	gzip -c $(IMG) > gk802_debian_installer.img.gz

clean:
	rm -rf build/* $(IMG) *.deb
	make -C uboot clean
	make -C kernel clean

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
	cd kernel && $(MAKE_KPKG) kernel_image


# Installer initrd

build/uInitRdInstaller: build/initrd.gz
	mkimage -A arm -O linux -T ramdisk -a 0x11008000 -n "GK802 Debian netinst initrd" -d build/initrd.gz build/uInitRdInstaller

build/initrd.gz: build/installer_root
	cd build/installer_root && find . | fakeroot cpio -H newc -o | gzip -c > ../initrd.gz

# Installer root directory, used as contents of the initrd
build/installer_root: src/vexpress-initrd.gz uboot/u-boot.imx src/finish-install.d/* src/base-installer.d/* $(DEB) src/install_kernel_uboot.sh src/ubootcmd.src build/kernel_unpacked/lib/modules src/preseed.cfg src/update_ubootcmd.sh
	mkdir -p $@
	cd $@ && zcat ../../src/vexpress-initrd.gz | fakeroot cpio -id
	rm -rf $@/lib/modules/*
	fakeroot cp -a build/kernel_unpacked/lib/modules/* $@/lib/modules
	mkdir -p $@/gk802_components
	fakeroot cp -a uboot/u-boot.imx $(DEB) src/install_kernel_uboot.sh src/ubootcmd.src src/update_ubootcmd.sh $@/gk802_components
	fakeroot cp -a src/finish-install.d/* $@/usr/lib/finish-install.d/
	fakeroot cp -a src/base-installer.d/* $@/usr/lib/base-installer.d/
	fakeroot cp -a src/preseed.cfg $@/
	touch build/installer_root

build/kernel_unpacked/boot: $(DEB)
	mkdir -p build/kernel_unpacked
	dpkg -x $(DEB) build/kernel_unpacked


# Partition image for the installer disk image
#
# (This is a simple image that just contains the zImage and the initrd for
# the installer, and a uboot command script to boot it.)
build/partition_root: build/zImageInstaller build/uInitRdInstaller src/ubootcmd_installer.src
	mkdir -p $@
	cp build/zImageInstaller build/uInitRdInstaller $@
	mkimage -T script -C none -n "GK802 Debian installer" -d src/ubootcmd_installer.src $@/ubootcmd
	touch $@

BLOCKS = $(shell echo $$(( $$(du -s --block-size=512 build/partition_root/ | cut -f1) + 500 )) )
build/partition.img: build/partition_root
	genext2fs -b $(BLOCKS) -m 0 -U -d build/partition_root build/partition.img

# Extract the installation zImage from the desktop kernel deb
build/zImageInstaller: build/kernel_unpacked/boot
	cp build/kernel_unpacked/boot/$(VMLINUZ) build/zImageInstaller

$(IMG): build/partition.img uboot/u-boot.imx
	dd if=build/partition.img of=$(IMG) bs=512 seek=2048
	sfdisk --force $(IMG) < src/sfdisk_partition.txt
	dd if=uboot/u-boot.imx of=$(IMG) bs=1k seek=1 conv=notrunc


