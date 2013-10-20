#!/bin/bash
#
# requires:
#  bash
#
set -e
set -x

# variables

declare filepath=$1
declare disk_filename=zxcv.raw

# validate

[[ $UID == 0 ]] || { echo "Must run as root." >&2; exit 1; }
[[ -f "${filepath}" ]] || { echo "file not found: ${filepath}" >&2; exit 1; }
size=$(stat -c %s ${filepath})

# main

## disk

truncate -s ${size}  ${disk_filename}

## mbr

lodev=$(losetup -f)
losetup ${lodev} ${disk_filename}
dd if=${filepath} of=${lodev} bs=512 count=1
udevadm settle
losetup -d ${lodev}

## partition

rootfs_part=$(kpartx -va ${disk_filename} | egrep "^add map " | head -1 | awk '{print $3}')
rootfs_dev=/dev/mapper/${rootfs_part}
udevadm settle

mkfs.ext4 -F -E lazy_itable_init=1 ${rootfs_dev}
blkid -c /dev/null -sUUID -ovalue  ${rootfs_dev}

tune2fs -L root ${rootfs_dev}
e2label         ${rootfs_dev}

### work-around ###
chroot_dir=mnt2

mount ${rootfs_dev} ${chroot_dir}
time rsync -aHA --delete mnt1/ ${chroot_dir}
time sync

root_dev="hd0"
tmpdir=/tmp/vmbuilder-grub

new_filename=${tmpdir}/${disk_filename##*/}
mkdir -p ${chroot_dir}/${tmpdir}

touch ${chroot_dir}/${new_filename}
mount --bind ${disk_filename} ${chroot_dir}/${new_filename}

devmapfile=${tmpdir}/device.map
touch ${chroot_dir}/${devmapfile}

disk_id=0
printf "(hd%d) %s\n" ${disk_id} ${new_filename} >>  ${chroot_dir}/${devmapfile}
cat ${chroot_dir}/${devmapfile}

mkdir -p ${chroot_dir}/${tmpdir}

grub_cmd="chroot ${chroot_dir} grub --batch --device-map=${devmapfile}"
cat <<-_EOS_ | ${grub_cmd}
	root (${root_dev},0)
	setup (hd0)
	quit
	_EOS_

umount ${chroot_dir}/${new_filename}
umount ${chroot_dir}

kpartx -vd ${disk_filename}
udevadm settle

sync
