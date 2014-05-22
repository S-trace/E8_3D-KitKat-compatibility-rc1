#!/bin/bash
build=`cat build`
cd ramdisk 
sudo chown root:root -R ramdisk
sudo find| sudo cpio -H newc -o | gzip -9 > ../ramdisk_$build.cpio.gz
cd ..
sudo chown s-trace:s-trace -R ramdisk
./mkbootimg --kernel boot.img-zImage --ramdisk ramdisk_CM11.gz --base 0x80008000 --pagesize 2048 -o boot_$build.img
echo boot_$build.img built
let build=build+1
echo $build > build
# adb reboot recovery
until adb push boot_$build.img /sdcard/; do sleep 1 ; done
adb shell flash_image boot /sdcard/boot_$build.img
