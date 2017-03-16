#!/usr/bin/env bash
set -e
# Usage:
#   DEVICES=(/dev/xvd{f..i}) MOUNTPOINT="/var/lib/postgresql" \
#   MOUNTOPTS="relatime,nofail" CONF="/etc/mdadm/mdadm.conf" LABEL="PGDATA" \
#   MD="/dev/md127" FS="xfs" RAID="ebs" /path/to/mdadm.sh
# Opts:
#   FS=<xfs|ext4>
#   RAID=<ebs|ephemeral|noraid>

DEVICES=(${DEVICES[@]:?})
MOUNTPOINT="${MOUNTPOINT:?}"
MOUNTOPTS="${MOUNTOPTS:-nobootwait,nofail}"
CONF="${CONF:-/etc/mdadm/mdadm.conf}"
LABEL="${LABEL:?}"
MD="${MD:-/dev/md127}"
FS="${FS:-xfs}"
RAID="${RAID:-ebs}"

function prepareenv  { mkdir -p "${CONF%/*}"; mkdir -p "${MOUNTPOINT}"; }
function createconf  { echo "DEVICE ${DEVICES[@]}" | tee ${CONF}; mdadm --detail --scan | tee -a ${CONF}; }
function createfs    { mkfs.${FS} -L ${LABEL} -f ${MD}; }
function mountfs     { mountpoint -q ${MOUNTPOINT} || mount ${MD} ${MOUNTPOINT}; }
function umountfs    { mountpoint -q ${MOUNTPOINT} || return 0 && umount ${MOUNTPOINT}; }
function createmd    { echo y | mdadm --create ${MD} --level=0 --raid-devices=${#DEVICES[@]} ${DEVICES[@]}; }
function exammd      { mdadm --examine ${DEVICES[@]}; }
function stopmd      { mdadm --stop ${MD}; }
function removemd    { mdadm --remove ${MD}; }
function destroymd   { mdadm --zero-superblock ${DEVICES[@]}; }
function destroyconf { [[ -s ${CONF} ]] || return 0 && rm -rf "${CONF%/*}"; }
function lookupdev   { printf "%s\n" "${DEVICES[@]##*/}" | grep -cwof - /proc/partitions; }
function statusdev   { [[ -s ${CONF} ]] && { [[ -b ${MD} ]] || return 0; }; exammd; }
function validatedev { if n=$( lookupdev ); then [[ ${n} -eq ${#DEVICES[@]} ]] || exit 1; fi; }
function addfstab    { echo "LABEL=${LABEL} ${MOUNTPOINT} ${FS} ${MOUNTOPTS} 0 0" | tee -a /etc/fstab >/dev/null; }
function delfstab    { grep -v "LABEL=${LABEL} ${MOUNTPOINT} ${FS} ${MOUNTOPTS} 0 0" /etc/fstab > /tmp/fstab; mv -f /tmp/fstab /etc/fstab; }
function createlabel { [[ ${FS} == ext[234] ]] && tune2fs -L ${LABEL} ${MD}; [[ ${FS} == xfs ]] && xfs_admin -L ${LABEL} ${MD}; }
function finish      { exit 0; }

CMD=${@:-create}
[[ ${RAID} == noraid  ]] && { validatedev; prepareenv; createlabel; addfstab; mountfs && finish || finish; }
[[ ${CMD}  == status  ]] && { statusdev && finish; }
[[ ${CMD}  == create  ]] && { validatedev; prepareenv; createmd; createfs; createlabel; createconf; addfstab; mountfs && finish; }
[[ ${CMD}  == destroy ]] && { umountfs; delfstab; destroyconf; stopmd; destroymd && finish; }
