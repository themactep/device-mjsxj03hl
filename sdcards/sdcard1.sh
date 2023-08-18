#!/bin/bash
#
# Create SD card #1
# for flashing OpenIPC firmware
# to a Xiaomi MJSXJ03HL camera
#
# 2023 Paul Philippov, paul@themactep.com
#

show_help() {
    echo "Usage: $0 -d <SD card device>"
    if [ "$EUID" -eq 0 ]; then
        echo -n "Detected devices: "
        fdisk -x | grep -B1 'SD/MMC' | head -1 | awk '{print $2}' | sed 's/://'
    fi
    exit 2
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    show_help
    exit 1
fi

# command line arguments
while getopts d: flag; do
    case ${flag} in
        d) card_device=${OPTARG} ;;
    esac
done

if [ -z "$card_device" ]; then
    show_help
    exit 3
fi

if [ ! -e "$card_device" ]; then
    echo "Device $card_device not found."
    exit 4
fi

while mount | grep $card_device > /dev/null; do
    umount $(mount | grep $card_device | awk '{print $1}')
done

read -p "All existing information on the card will be lost! Proceed? [Y/N]: " ret
if [ "$ret" != "Y" ]; then
    echo "Aborting!"
    exit 99
fi

echo "Creating a 64MB FAT32 partition on the SD card."
parted -s ${card_device} mklabel msdos mkpart primary fat32 1MB 64MB && mkfs.vfat ${card_device}1 > /dev/null
if [ $? -ne 0 ]; then
    echo "Cannot create a partition."
    exit 4
fi

sdmount=$(mktemp -d)

echo "Mounting the partition to ${sdmount}."
if ! mkdir -p $sdmount; then
    echo "Cannot create ${sdmount}."
    exit 5
fi

if ! mount ${card_device}1 $sdmount; then
    echo "Cannot mount ${card_device}1 to ${sdmount}."
    exit 6
fi

echo "Downloading the latest OpenIPC firmware image."
if ! wget -q -O ${sdmount}/openipc-t31n-lite-8mb.bin "https://openipc.org/cameras/vendors/ingenic/socs/t31n/download_full_image?flash_size=8&flash_type=nor&fw_release=lite"; then
    echo "Cannot download openipc image."
    exit 7
fi

echo "Unmounting the SD partition."
sync
umount $sdmount
eject $card_device

echo "
Card #1 created successfully.
The card is unmounted. You can safely remove it from the slot.

To install the OpenIPC firmware, login into camera bootloader shell
and run the following commands:

setenv baseaddr 0x80600000
setenv flashsize 0x1000000
mw.b \${baseaddr} 0xff \${flashsize}
fatload mmc 0:1 \${baseaddr} openipc-t31n-lite-8mb.bin
sf probe 0
sf erase 0x0 \${flashsize}
sf write \${baseaddr} 0x0 \${flashsize}
reset
"

exit 0
