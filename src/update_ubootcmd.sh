#!/bin/sh

# regenerate boot script
/usr/bin/mkimage -T script -C none -n "Debian GK802 boot script" -d /boot/ubootcmd.src /boot/ubootcmd

