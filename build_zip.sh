#!/bin/bash
mkimg(){
  # Call: mkimg type modification
  pushd ${1} > /dev/null
  find | cpio --create --format=newc --owner=root:root --file=../${1}_${2}.cpio
  popd > /dev/null
  
  pushd ${1}_${2} > /dev/null
  find | cpio --create --append --format=newc --owner=root:root --file=../${1}_${2}.cpio
  popd > /dev/null
  
  gzip ${1}_${2}.cpio
  ./mkbootimg --kernel Kernel_${2}.uImage --ramdisk ${1}_${2}.cpio.gz --base 0x80008000 --pagesize 2048 -o ${1}_${2}.img
  echo ${1}_${2}.img built
  mv ${1}_${2}.img ../${1}_${2}.img
  rm ${1}_${2}.cpio.gz
}

build=`cat build`

pushd boot > /dev/null
setfacl --restore=permissions.acl
mkimg boot EXT4_classic
mkimg boot EXT4_datamedia
mkimg boot UBIFS_classic
mkimg boot UBIFS_datamedia
mkimg recovery EXT4_classic
mkimg recovery EXT4_datamedia
mkimg recovery UBIFS_classic
mkimg recovery UBIFS_datamedia
popd > /dev/null

let build_next=build+1
echo $build_next > build
# adb reboot recovery

rm -rf out/
mkdir -p out/

zip out/E8_3D-cm11.0-compatibility-rc1_rev${build}.zip META-INF system specific build_prop_patcher.sh boot_*.img -r
echo out/E8_3D-cm11.0-compatibility-rc1_rev${build}.zip built
zip out/E8_3D-cm11.0-compatibility-rc1_rev${build}_helpers.zip aml_autoscript Init_FS_after_NAND_scrub.zip u-boot.bin
echo out/E8_3D-cm11.0-compatibility-rc1_rev${build}_helpers.zip built

for file in recovery_*.img ; do 
  zip out/$file.zip $file
  echo out/$file.zip built
done

until adb push out/E8_3D-cm11.0-compatibility-rc1_rev${build}.zip /sdcard/; do sleep 1 ; done
#until adb push out/E8_3D-cm11.0-compatibility-rc1_rev${build}.zip /media/; do sleep 1 ; done
# until adb push boot.img /tmp/; do sleep 1 ; done
# until adb shell flash_image boot /tmp/boot.img; do sleep 1 ; done
echo Compat ${build} built
