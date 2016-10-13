#!/usr/bin/env bash
set -e
DEVICES=(${DEVICES[@]:-/dev/xvdb /dev/xvdc}) \
  MOUNTPOINT="${MOUNTPOINT:-/var/lib/cassandra/data}" \
  CONF="${CONF:-/etc/mdadm/mdadm.conf}" \
  MD="${MD:-/dev/md127}" \
  FS="${FS:-xfs}"

function prepareenv  { mkdir -p "${CONF%/*}"; mkdir -p "${MOUNTPOINT}"; }
function createconf  { echo "DEVICE ${DEVICES[@]}" | tee ${CONF}; mdadm --detail --scan | tee -a ${CONF}; }
function createfs    { mkfs.${FS} -f ${MD} -L ${HOSTNAME%%\.*}; }
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

CMD=${@:-create}
[[ ${CMD} == status ]]  && { statusdev; }
[[ ${CMD} == create ]]  && { validatedev; prepareenv; createmd; createfs; createconf; mountfs; }
[[ ${CMD} == destroy ]] && { umountfs; destroyconf; stopmd; destroymd; }
