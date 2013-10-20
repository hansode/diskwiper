#!/bin/bash
#
# requires:
#  bash
#
set -e
set -x

# variables

declare src_filepath=$1
declare dst_filepath=zxcv.raw

# validate

function checkroot() {
  #
  # Check if we're running as root, and bail out if we're not.
  #
  [[ "${UID}" -ne 0 ]] && {
    echo "[ERROR] Must run as root." >&2
    return 1
  } || :
}
checkroot

[[ -f "${src_filepath}" ]] || { echo "file not found: ${src_filepath}" >&2; exit 1; }
size=$(stat -c %s ${src_filepath})

# main

## disk

truncate -s ${size} ${dst_filepath}

## mbr

function copy_mbr() {
  local src_filepath=$1 dst_filepath=$2
  local lodev=$(losetup -f)

  losetup ${lodev} ${dst_filepath}
  dd if=${src_filepath} of=${lodev} bs=512 count=1

  udevadm settle
  losetup -d ${lodev}
}
copy_mbr ${src_filepath} ${dst_filepath}

## partition

function lspart() {
  local filepath=$1

  # $ sudo parted centos-6.4_x86_64.raw print | sed "1,/^Number/d" | egrep -v '^$'
  #  1      32.3kB  4294MB  4294MB  primary  ext4
  #  2      4295MB  5368MB  1073MB  primary  linux-swap(v1)

  parted ${filepath} print | sed "1,/^Number/d" | egrep -v '^$' | awk '{print $1, $6}'
}

function lspartmap() {
  local disk_filepath=$1

  # $ sudo kpartx -va centos-6.4_x86_64.raw
  # add map loop0p1 (253:0): 0 8386498 linear /dev/loop0 63
  # add map loop0p2 (253:1): 0 2095104 linear /dev/loop0 8388608

  local kpartx_output=$(kpartx -va ${disk_filepath})
  udevadm settle
  echo "${kpartx_output}" \
  | egrep "^add map" \
  | awk '{print $3}' \
  | sed 's,[0-9]$,,' \
  | uniq
}

function tmpdir_path() {
  echo /tmp/tmp$(date +%s.%N)
}

function sync_ptab() {
  local src_filepath=$1 dst_filepath=$2
  local src_lodev=$(lspartmap ${src_filepath})
  local dst_lodev=$(lspartmap ${dst_filepath})

  local line
  while read line; do
    set ${line}

    local src_part_filename=/dev/mapper/${src_lodev}${1}
    local dst_part_filename=/dev/mapper/${dst_lodev}${1}

    local src_disk_uuid=$(blkid -c /dev/null -sUUID -ovalue ${src_part_filename})

    case "${2}" in
    *swap*)
      mkswap -f -L swap -U ${src_disk_uuid} ${dst_part_filename}
      ;;
    ext*)
      local src_part_label=$(e2label ${src_part_filename})
      [[ -z "${src_part_label}" ]] || tune2fs -L ${src_part_label} ${dst_part_filename}
      mkfs.ext4 -F -E lazy_itable_init=1 -U ${src_disk_uuid} ${dst_part_filename}
      tune2fs -c 0 -i 0 ${dst_part_filename}
      tune2fs -o acl    ${dst_part_filename}

      local src_mnt=$(tmpdir_path)
      local dst_mnt=$(tmpdir_path)

      mkdir -p ${src_mnt}
      mkdir -p ${dst_mnt}

      mount ${src_part_filename} ${src_mnt}
      mount ${dst_part_filename} ${dst_mnt}

      rsync -aHA ${src_mnt}/ ${dst_mnt}
      sync

      umount -l ${src_mnt}
      umount -l ${dst_mnt}

      rmdir ${src_mnt}
      rmdir ${dst_mnt}
      ;;
    *)
      ;;
    esac
  done < <(lspart ${src_filepath})
  udevadm settle
}
sync_ptab ${src_filepath} ${dst_filepath}

## bootloader

function setup_bootloader() {
  local src_filepath=$1 dst_filepath=$2

  local dst_lodev=$(lspartmap ${dst_filepath})

  local rootfs_dev=
  while read line; do
    set ${line}
    case "${2}" in
    ext*|*)
      [[ -n "${rootfs_dev}" ]] || rootfs_dev=/dev/mapper/${dst_lodev}${1}
    esac
  done < <(lspart ${src_filepath})

  local chroot_dir=/tmp/tmp$(date +%s.%N)
  mkdir -p ${chroot_dir}
  mount ${rootfs_dev} ${chroot_dir}
  cat ${chroot_dir}/etc/fstab

  local root_dev="hd0"
  local tmpdir=/tmp/vmbuilder-grub

  local new_filename=${tmpdir}/${dst_filepath##*/}
  mkdir -p ${chroot_dir}/${tmpdir}

  touch ${chroot_dir}/${new_filename}
  mount --bind ${dst_filepath} ${chroot_dir}/${new_filename}

  local devmapfile=${tmpdir}/device.map
  touch ${chroot_dir}/${devmapfile}

  local disk_id=0
  printf "(hd%d) %s\n" ${disk_id} ${new_filename} >>  ${chroot_dir}/${devmapfile}
  cat ${chroot_dir}/${devmapfile}

  mkdir -p ${chroot_dir}/${tmpdir}

  local grub_cmd="chroot ${chroot_dir} grub --batch --device-map=${devmapfile}"
  cat <<-_EOS_ | ${grub_cmd}
	root (${root_dev},0)
	setup (hd0)
	quit
	_EOS_

  umount ${chroot_dir}/${new_filename}
  umount ${chroot_dir}
  rmdir  ${chroot_dir}
}
setup_bootloader ${src_filepath} ${dst_filepath}

kpartx -vd ${src_filepath}
kpartx -vd ${dst_filepath}
