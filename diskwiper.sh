#!/bin/bash
#
# requires:
#  bash
#  sed, egrep, awk, uniq, cat, chroot
#  mkdirm, rmdir, mount, umount, rsync
#  truncate, losetup, dd, udevadm, parted, kpartx
#  blkid, mkswap, mkfs.ext4, tune2fs
#
set -e
set -x
set -o pipefail

## utils

function checkroot() {
  #
  # Check if we're running as root, and bail out if we're not.
  #
  [[ "${UID}" -ne 0 ]] && {
    echo "[ERROR] Must run as root." >&2
    return 1
  } || :
}

## disk

function mkdisk() {
  #
  # Creates the disk image (if it doesn't already exist).
  #
  local disk_filename=$1 size=${2:-0} unit=${3:-m}
  [[ -a "${disk_filename}" ]] && { echo "[ERROR] already exists: ${disk_filename} (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ "${size}" -gt 0 ]] || { echo "[ERROR] Invalid argument: size:${size} (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }

  truncate -s ${size}${unit} ${disk_filename}
}

## mbr

function cpmbr() {
  local src_filename=$1 dst_filename=$2

  local lodev=$(losetup -f)
  losetup ${lodev} ${dst_filename}
  # count=
  # - NG  1..27
  # - OK 28..63
  #
  # count=63 means to copy partition-table and bootloader(grub stage1.5)
  dd if=${src_filename} of=${lodev} bs=512 count=63
  udevadm settle
  losetup -d ${lodev}
}

## partition

function lspart() {
  local disk_filename=$1

  # $ sudo parted centos-6.4_x86_64.raw print | sed "1,/^Number/d" | egrep -v '^$'
  #  1      32.3kB  4294MB  4294MB  primary  ext4
  #  2      4295MB  5368MB  1073MB  primary  linux-swap(v1)
  parted ${disk_filename} print \
  | sed "1,/^Number/d" \
  | egrep -v '^$' \
  | awk '{print $1, $6}'
}

function getdmname() {
  local disk_filename=$1

  # $ sudo kpartx -va centos-6.4_x86_64.raw
  # add map loop0p1 (253:0): 0 8386498 linear /dev/loop0 63
  # add map loop0p2 (253:1): 0 2095104 linear /dev/loop0 8388608
  local kpartx_output=$(kpartx -va ${disk_filename})
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

function cpptab() {
  local src_filename=$1 dst_filename=$2

  local src_lodev=$(getdmname ${src_filename})
  local dst_lodev=$(getdmname ${dst_filename})

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
      mkfs.ext4 -F -E lazy_itable_init=1 -U ${src_disk_uuid} ${dst_part_filename}
      tune2fs -c 0 -i 0 ${dst_part_filename}
      tune2fs -o acl    ${dst_part_filename}

      local src_part_label=$(e2label ${src_part_filename})
      if [[ -n "${src_part_label}" ]]; then
         tune2fs -L ${src_part_label} ${dst_part_filename}
      fi

      local src_mnt=$(tmpdir_path)
      local dst_mnt=$(tmpdir_path)

      mkdir -p ${src_mnt}
      mkdir -p ${dst_mnt}

      mount ${src_part_filename} ${src_mnt}
      mount ${dst_part_filename} ${dst_mnt}

      rsync -aHA ${src_mnt}/ ${dst_mnt}
      sync

      umount ${src_mnt}
      umount ${dst_mnt}

      rmdir ${src_mnt}
      rmdir ${dst_mnt}
      ;;
    *)
      ;;
    esac
  done < <(lspart ${src_filename})
  udevadm settle
}

## diskwiper

function diskwiper() {
  local src_filename=$1 dst_filename=$2

  mkdisk ${dst_filename} $(stat -c %s ${src_filename}) " "
  cpmbr  ${src_filename} ${dst_filename}
  cpptab ${src_filename} ${dst_filename}

  kpartx -vd ${src_filename}
  kpartx -vd ${dst_filename}
}

## environment variables

export LANG=C
export LC_ALL=C

## variables

declare src_filename=$1
declare dst_filename=${2:-zxcv.raw}

## main

checkroot
[[ -f "${src_filename}" ]] || { echo "file not found: ${src_filename}" >&2; exit 1; }
diskwiper ${src_filename} ${dst_filename}
