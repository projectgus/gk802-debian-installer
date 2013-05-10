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
DEB = linux-image-$(KERNELVER)-$(KERNELREV)-gk802-$(1)_$(KERNELVER).$(DEBIAN_REVISION)_armhf.deb
APPEND_TO_VERSION = "-$(KERNELREV)-gk802-$(1)"

DESKTOP_DEB=$(call DEB,desktop)
HEADLESS_DEB=$(call DEB,headless)

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

$(DESKTOP_DEB): src/config-desktop
	cp src/config-desktop kernel/.config
	cd kernel && $(MAKE_KPKG) clean
	cd kernel && make oldconfig
	cd kernel && $(MAKE_KPKG) --append-to-version $(call APPEND_TO_VERSION,desktop) kernel_image

$(HEADLESS_DEB): src/config-headless
	cp src/config-headless kernel/.config
	cd kernel && $(MAKE_KPKG) clean
	cd kernel && make oldconfig
	cd kernel && $(MAKE_KPKG) --append-to-version $(call APPEND_TO_VERSION,headless) kernel_image


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
build/installer_zImage: build/desktop_kernel_unpacked/boot
	cp build/desktop_kernel_unpacked/boot/vmlinuz* build/installer_zImage

build/desktop_kernel_unpacked/boot: $(DESKTOP_DEB)
	mkdir -p build/desktop_kernel_unpacked
	dpkg -x $(DESKTOP_DEB) build/desktop_kernel_unpacked

# Installer initrd

build/uInitRdInstaller: build/initrd.gz
	mkimage -A arm -O linux -T ramdisk -a 0x11008000 -n "GK802 Debian netinst initrd" -d build/initrd.gz build/uInitRdInstaller

build/initrd.gz: build/installer_root
	cd build/installer_root && find . | fakeroot cpio -H newc -o | gzip -c > ../initrd.gz

# Installer root directory, used as contents of the initrd
build/installer_root: src/vexpress-initrd.gz uboot/u-boot.imx src/19install_gk802_components $(DESKTOP_DEB) $(HEADLESS_DEB) src/install_kernel.sh src/ubootcmd.src build/desktop_kernel_unpacked/lib/modules
	mkdir -p $@
	cd $@ && zcat ../../src/vexpress-initrd.gz | fakeroot cpio -id
	rm -rf $@/lib/modules/*
	cp -r build/desktop_kernel_unpacked/lib/modules/* $@/lib/modules
	mkdir -p $@/gk802_components
	cp uboot/u-boot.imx $(DESKTOP_DEB) $(HEADLESS_DEB) src/install_kernel.sh src/ubootcmd.src $@/gk802_components
	chmod +x $@/gk802_components/install_kernel.sh
	cp src/19install_gk802_components $@/usr/lib/finish-install.d/
	chmod +x $@/usr/lib/finish-install.d/19install_gk802_components
	touch build/installer_root

