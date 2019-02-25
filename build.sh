#!/bin/sh
# vim: set noet :

set -eux

################################################################################
# Command Line Options
################################################################################

while getopts 'a:b:d:i:k:m:p:r:t:hv' OPTION; do
	case "$OPTION" in
		a) ARCH="$OPTARG";;
		b) ALPINE_BRANCH="$OPTARG";;
		d) CHROOT_DIR="$OPTARG";;
		i) BIND_DIR="$OPTARG";;
		k) CHROOT_KEEP_VARS="${CHROOT_KEEP_VARS:-} $OPTARG";;
		m) ALPINE_MIRROR="$OPTARG";;
		p) ALPINE_PACKAGES="${ALPINE_PACKAGES:-} $OPTARG";;
		r) EXTRA_REPOS="${EXTRA_REPOS:-} $OPTARG";;
		t) TEMP_DIR="$OPTARG";;
	esac
done

################################################################################
# Default Environment Variables
################################################################################

: ${ALPINE_BRANCH:="v3.9"}
: ${ALPINE_MIRROR:="http://dl-cdn.alpinelinux.org/alpine"}
: ${ALPINE_PACKAGES:="build-base ca-certificates ssl_client"}
: ${ARCH:=}
: ${BIND_DIR:=}
: ${CHROOT_DIR:="/alpine-build-${ARCH}"}
: ${CHROOT_KEEP_VARS:="ARCH CI QEMU_EMULATOR CIRCLE_.* TRAVIS_.*"}
: ${EXTRA_REPOS:=}
: ${TEMP_DIR:=$(mktemp -d || echo /tmp/alpine)}
: ${BUILD_DIR:="${TEMP_DIR}/build"}
: ${BLOCK_DEV:="/dev/nbd0"}

################################################################################
# Initialize
################################################################################

# Load Kernel Module
lsmod | grep -qs nbd || modprobe nbd

# Install Required Packages
dpkg -l | awk '{print $1}' | grep -qs '^gdisk$'              || apt-get -y --no-install-recommends install gdisk
dpkg -l | awk '{print $1}' | grep -qs '^dosfstools$'         || apt-get -y --no-install-recommends install dosfstools
dpkg -l | awk '{print $1}' | grep -qs '^e2fsprogs$'          || apt-get -y --no-install-recommends install e2fsprogs
dpkg -l | awk '{print $1}' | grep -qs '^pixz$'               || apt-get -y --no-install-recommends install pixz
dpkg -l | awk '{print $1}' | grep -qs '^grub-pc-bin$'        || apt-get -y --no-install-recommends install grub-pc-bin
dpkg -l | awk '{print $1}' | grep -qs '^grub-efi-amd64-bin$' || apt-get -y --no-install-recommends install grub-efi-amd64-bin

# Unmount RootFs
awk '{print $2}' /proc/mounts | grep -s "${CHROOT_DIR}" | sort -r | xargs --no-run-if-empty umount

################################################################################
# Disk
################################################################################

# Create Build Directory
mkdir -p "${BUILD_DIR}"

# Create Disk Image
qemu-img create -q -f qcow2 "${BUILD_DIR}/box.img" 32G

# Connect Disk Image
qemu-nbd -c "${BLOCK_DEV}" "${BUILD_DIR}/box.img"

# Clear Partition Table
sgdisk -Z "${BLOCK_DEV}"

# Create GPT Partition Table
sgdisk -o "${BLOCK_DEV}"

# Create BIOS Partition
sgdisk -a 1 -n 1::2047  -c 1:"Bios" -t 1:ef02 "${BLOCK_DEV}"

# Create EFI Partition
sgdisk      -n 2::+512M -c 2:"Efi"  -t 2:ef00 "${BLOCK_DEV}"

# Create Root Partition
sgdisk      -n 3::-1    -c 3:"Root" -t 3:8300 "${BLOCK_DEV}"

# Root File System Partition
mkfs.ext4 -L "RootFs" "${BLOCK_DEV}p3"
mkdir -p "${CHROOT_DIR}"
mount "${BLOCK_DEV}p3" "${CHROOT_DIR}"

# EFI System Partition
mkfs.vfat -F 32 -n "EfiFs" "${BLOCK_DEV}p2"
mkdir -p "${CHROOT_DIR}/boot/efi"
mount "${BLOCK_DEV}p2" "${CHROOT_DIR}/boot/efi"

################################################################################
# Chroot
################################################################################

# Export Environment Variables
export ALPINE_BRANCH="${ALPINE_BRANCH}"
export ALPINE_MIRROR="${ALPINE_MIRROR}"
export ALPINE_PACKAGES="${ALPINE_PACKAGES}"
export ARCH="${ARCH}"
export BIND_DIR="${BIND_DIR}"
export CHROOT_DIR="${CHROOT_DIR}"
export CHROOT_KEEP_VARS="${CHROOT_KEEP_VARS}"
export EXTRA_REPOS="${EXTRA_REPOS}"
export TEMP_DIR="${TEMP_DIR}"

# Build Alpine Base Image
./alpine-chroot-install/alpine-chroot-install

# Install Bios Boot Recode
case "${ARCH}" in
	"x86_64" )
		${CHROOT_DIR}/enter-chroot apk add --no-cache grub-bios grub-efi
		${CHROOT_DIR}/enter-chroot grub-install --recheck --target=i386-pc "${BLOCK_DEV}"
		${CHROOT_DIR}/enter-chroot grub-install --recheck --target=x86_64-efi --efi-directory=/boot/efi
		;;
	"aarch64" )
		${CHROOT_DIR}/enter-chroot apk add --no-cache grub-efi
		${CHROOT_DIR}/enter-chroot grub-install --recheck --target=x86_64-efi --efi-directory=/boot/efi
		;;
esac

# Unmount RootFs
awk '{print $2}' /proc/mounts | grep -s "${CHROOT_DIR}" | sort -r | xargs --no-run-if-empty umount

# Disconnect Disk Image
qemu-nbd -d "${BLOCK_DEV}" > /dev/null

################################################################################
# Vagrant Box
################################################################################

# Create Vagrant Configuration File
cat > "${BUILD_DIR}/Vagrantfile" << '__EOF__'
Vagrant.configure("2") do |config|
  config.vm.provider :libvirt do |libvirt|
    libvirt.driver = "kvm"
  end
end
__EOF__

# Create Vagrant Metadata File
cat > "${BUILD_DIR}/metadata.json" << '__EOF__'
{"format":"qcow2","provider":"libvirt","virtual_size":32}
__EOF__

# Create Vagrant Boxes
tar -cvf "alpine-linux-${ARCH}-${ALPINE_BRANCH}.box" -C "${BUILD_DIR}" -I pixz .
