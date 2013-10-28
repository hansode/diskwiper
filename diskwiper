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
  local src_disk=$1 dst_disk=$2

  local lodev=$(losetup -f)
  losetup ${lodev} ${dst_disk}
  #
  # count:
  # - NG  1..27
  # - OK 28..63
  #
  # "count=63" means to copy partition-table and bootloader(grub stage1.5)
  #
  dd if=${src_disk} of=${lodev} bs=512 count=63
  losetup -d ${lodev}
}

## partition

function lspartmap() {
  local disk_filename=$1

  #
  # $ sudo parted centos-6.4_x86_64.raw print | sed "1,/^Number/d" | egrep -v '^$'
  #  1      32.3kB  4294MB  4294MB  primary  ext4
  #  2      4295MB  5368MB  1073MB  primary  linux-swap(v1)
  #
  # $ [command] | awk '{print $1, $6}'
  # 1 ext4
  # 2 linux-swap(v1)
  #
  parted ${disk_filename} print \
  | sed "1,/^Number/d" \
  | egrep -v '^$' \
  | awk '{print $1, $6}'
}

function getdmname() {
  local disk_filename=$1

  #
  # $ sudo kpartx -va centos-6.4_x86_64.raw
  # add map loop0p1 (253:0): 0 8386498 linear /dev/loop0 63
  # add map loop0p2 (253:1): 0 2095104 linear /dev/loop0 8388608
  #
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
  local src_disk=$1 dst_disk=$2

  local src_lodev=$(getdmname ${src_disk})
  local dst_lodev=$(getdmname ${dst_disk})

  local line part_index part_fstype
  while read line; do
    set ${line}
    part_index=${1}
    part_fstype=${2}

    local src_part=/dev/mapper/${src_lodev}${part_index}
    local dst_part=/dev/mapper/${dst_lodev}${part_index}

    local src_disk_uuid=$(blkid -c /dev/null -sUUID -ovalue ${src_part})

    case "${part_fstype}" in
    *swap*)
      mkswap -f -L swap -U ${src_disk_uuid} ${dst_part}
      ;;
    ext*)
      mkfs.ext4 -F -E lazy_itable_init=1 -U ${src_disk_uuid} ${dst_part}
      #
      # -c max-mount-counts
      # -i interval-between-checks[d|m|w]
      # -o [^]mount-option[,...]
      # acl    Enable Posix Access Control Lists.
      #
      tune2fs -c 0 -i 0 -o acl ${dst_part}
      tune2fs -l ${dst_part}

      local src_part_label=$(e2label ${src_part})
      if [[ -n "${src_part_label}" ]]; then
         #
         # -L volume-label
         #
         tune2fs -L ${src_part_label} ${dst_part}
      fi

      local src_mnt=$(tmpdir_path)
      local dst_mnt=$(tmpdir_path)

      mkdir -p ${src_mnt}
      mkdir -p ${dst_mnt}

      mount ${src_part} ${src_mnt}
      mount ${dst_part} ${dst_mnt}

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
  done < <(lspartmap ${src_disk})
}

## diskwiper

function diskwiper() {
  local src_disk=$1 dst_disk=$2

  local src_filesize=$(stat -c %s ${src_disk})
  mkdisk ${dst_disk} ${src_filesize} " "
  cpmbr  ${src_disk} ${dst_disk}
  cpptab ${src_disk} ${dst_disk}

  kpartx -vd ${src_disk}
  kpartx -vd ${dst_disk}
}

## environment variables

export LANG=C
export LC_ALL=C

## variables

declare src_disk=$1
declare dst_disk=${2:-zxcv.raw}

## main

checkroot
[[ -f "${src_disk}" ]] || { echo "file not found: ${src_disk}" >&2; exit 1; }
diskwiper ${src_disk} ${dst_disk}
