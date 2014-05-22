#!/bin/bash
build=`cat build`
sudo chown root:root -R ramdisk
cd ramdisk 
sudo find| sudo cpio -H newc -o | gzip -9 > ../ramdisk_$build.cpio.gz
cd ..
sudo chown s-trace:s-trace -R ramdisk
./mkbootimg --kernel boot.img-zImage --ramdisk ramdisk_CM11.gz --base 0x80008000 --pagesize 2048 -o boot_$build.img
echo boot_$build.img built
let build=build+1
echo $build > build
# adb reboot recovery
cp boot_$build.img ../
cd ..
zip -R NEO3DO_compat_$build.zip META-INF system addition
cd -
until adb push ../NEO3DO_compat_$build.zip /sdcard/; do sleep 1 ; done
until adb push boot_$build.img /sdcard/; do sleep 1 ; done
until adb shell flash_image boot /sdcard/boot_$build.img; do sleep 1 ; done

