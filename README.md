This is a hacky build process for creating a custom Debian Wheezy Installer derived SD card image that can be used to install Wheezy on a GK802 "AndroidTV" device.

As the term "hacky build process" suggests, this process is plenty hacky and doesn't even build debian-installer from source - it just takes the installer initrd image from the "vexpress" netinst (usually used for QEMU hosts) and then adds some additional scripts and stages to it. I know, it's *the worst*.

This repo could probably be reused to create hacky device-specific installers for other devices, assuming they have a working source-based kernel and a sane bootloader.

# On "doing it right"

It would have been good to do it properly, but lots of things involved in doing that (like creating kernel udebs for a non-debian cross-compiled kernel, or creating a kernel package to manage uboot installation for Freescale i.MX6), are non-trivial tasks that I didn't really know much about, or have the time/inclination to try and implement this time around. :).

If you're keen to do a "proper" version of this then please do, it'd be awesome!

The one non-hacky thing this installer does is install an actual kernel package, so you can upgrade kernels the Debian way, and also use Debian's initramfs system, etc. (possibly also dkms...)


# Installing Debian on a GK802 using this stuff

See [this blog post for a downloadable installer image and instructions](http://projectgus.com/2013/05/debian-installer-for-zealz-gk802-android-tv-quad-core-arm-minipc/).

# "Building" an image

Dependencies (assuming Debian/Ubuntu host):

    sudo apt-get install kernel-package fakeroot genext2fs gcc-arm-linux-gnueabihf
    sudo apt-get build-dep linux

(From memory, please tell me if incomplete...)

There are a few variables in the top of the Makefile that you might want to edit or override on the command line, for example the parallel make command.

Then just run 'make'. Don't run "make -jN", things will probably go wrong.

# Known Issues

* Is a giant hack so even though it works the implementation is icky.

* The Makefile's dependency management is a bit flaky, 'make clean' is the safe route :)

* Aside from these, please raise a github Issue if you find something that doesn't work but probably should.

# Useful bits to fiddle with

* `kernel/` is the actual kernel directory, it's a git submodule that points at my kernel fork by default but you can find other possible kernels at [imx6-dongle](https://github.com/imx6-dongle/linux-imx) or maybe even cherry-pick some commits from [Freescale's git repo](http://git.freescale.com/git/cgit.cgi/imx/linux-2.6-imx.git/) if you like. *May not work once you do this*.

* `src/config-server` is the kernel config used to build the image (be warned that if you change `kernel/.config`, it won't automatically update this file, in fact `kernel/.config` may find itself unexpectedly overwritten.

Compared to the current GK802 defconfig this config-server builds lots of things as modules, supports initramfs, and disables the GPU module, among other things.

* `src/uboot_extraconfig.h` contains some additional config options (autoboot timeout, raw initrd support) passed to uboot, on top of the usual gk802 defconfig.

* `src/install_kernel_uboot.sh` is a script that gets run during the "finish-install" stage, chrooted in the new Debian install, to install the GK802-specific kernel package and uboot.

* `src/vexpress-initrd.gz` is a Debian Wheezy initrd netinst image for the VExpress board (one of the few official Wheezy armhf installer images.)
