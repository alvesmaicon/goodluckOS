#!/bin/sh
# uboot-dtb.sh <rg351mp-kernel.dtb> - the R36H's battery in the factory U-Boot's DTB (BOOT's root), in place:
# its gauge gets the kernel DTS's OCV table (0 to 100 %, mV) and capacity. Needs fdtput (the dev container
# has it). Safe to run again.
set -e
b=/i2c@ff180000/pmic@20/battery
fdtput -t i "$1" $b ocv_table 3200 3400 3450 3500 3550 3570 3585 3605 3625 3650 3670 3700 3740 3790 3840 3895 3945 4005 4065 4115 4185
fdtput -t i "$1" $b design_capacity 2900
fdtput -t i "$1" $b design_qmax 3190
