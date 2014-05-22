#!/bin/bash

for i in `ls *.ko`; do
	/mnt/500G/amlogic/arm-2010q1/bin/arm-none-linux-gnueabi-strip --strip-unneeded $i
done
