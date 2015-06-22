#!/usr/bin/env bash
#
# Okay, so here's some real meat.  We take a drive (as 02 said, I use a VM),
# and we spray that stage4 all over it.  Then we rub some grub (0.97) all over
# it to make it feel better, and then we box it up and ship it out.

set -e -u -x

# Vars
export TEMP_DIR=${TEMP_DIR:-'/root/tmp/catalyst/gentoo'}
export MOUNT_DIR=${MOUNT_DIR:-'/mnt'}
export DATE=${DATE:-"$(date +%Y%m%d)"}
# profiles supported are as follows
# default/linux/amd64/13.0
# default/linux/amd64/13.0/no-multilib
# hardened/linux/amd64
# hardened/linux/amd64/no-multilib
# hardened/linux/amd64/selinux (eventually)
# hardened/linux/amd64/no-multilib/selinux (eventually)
export PROFILE=${PROFILE:-"default/linux/amd64/13.0"}
if [[ "${PROFILE}" == "default/linux/amd64/13.0" ]]; then
  PROFILE_SHORTNAME="amd64-default"
elif [[ "${PROFILE}" == "default/linux/amd64/13.0/no-multilib" ]]; then
  PROFILE_SHORTNAME="amd64-default-nomultilib"
elif [[ "${PROFILE}" == "hardened/linux/amd64" ]]; then
  PROFILE_SHORTNAME="amd64-hardened"
elif [[ "${PROFILE}" == "hardened/linux/amd64/no-multilib" ]]; then
  PROFILE_SHORTNAME="amd64-hardened-nomultilib"
else
  echo 'invalid profile, exiting'
  exit 1
fi
export TARBALL=${TARBALL:-"/root/tmp/catalyst/gentoo/stage4-${PROFILE_SHORTNAME}-${DATE}.tar.bz2"}
export TEMP_IMAGE=${TEMP_IMAGE:-"gentoo-${PROFILE_SHORTNAME}.img"}
export TARGET_IMAGE=${TARGET_IMAGE:-"/root/openstack-${PROFILE_SHORTNAME}-${DATE}.qcow2"}

# create a raw partition and do stuff with it
fallocate -l 5G "${TEMP_DIR}/${TEMP_IMAGE}"
losetup -f "${TEMP_DIR}/${TEMP_IMAGE}"
BLOCK_DEV=$(losetup | grep "${TEMP_IMAGE}" | awk '{print $1}')

# Okay, we have the disk, let's prep it
echo 'Building disk'
parted -s ${BLOCK_DEV} mklabel msdos
parted -s --align=none ${BLOCK_DEV} mkpart primary 2048s 100%
parted -s ${BLOCK_DEV} set 1 boot on
mkfs.ext4 -F ${BLOCK_DEV}p1

# Mount it
echo 'Mounting disk'
mkdir -p ${MOUNT_DIR}/${PROFILE_SHORTNAME}
mount ${BLOCK_DEV}p1 ${MOUNT_DIR}/${PROFILE_SHORTNAME}

# Expand the stage
echo 'Expanding tarball'
tar xjpf ${TARBALL} -C ${MOUNT_DIR}/${PROFILE_SHORTNAME}

# Throw in a resolv.conf
cp /etc/resolv.conf "${MOUNT_DIR}/${PROFILE_SHORTNAME}/etc/resolv.conf"

# Install grub
grub2-install ${BLOCK_DEV} --boot-directory ${MOUNT_DIR}/${PROFILE_SHORTNAME}/boot

# Clean up
echo 'Syncing; unmounting'
sync
umount ${MOUNT_DIR}/${PROFILE_SHORTNAME}

# get rid of block mapping
losetup -d ${BLOCK_DEV}

echo 'Converting raw image to qcow2'
qemu-img convert -c -f raw -O qcow2 ${TEMP_DIR}/${TEMP_IMAGE} ${TARGET_IMAGE}

echo 'Cleaning up'
rm "${TEMP_DIR}/${TEMP_IMAGE}"
