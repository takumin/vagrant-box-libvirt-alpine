#!/bin/sh
# vim: set noet :

set -eu

# Commandline Options
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

# Default Environment Variables
: ${BUILD_DIR:="build"}
: ${MOUNT_DIR:="mount"}
: ${BLOCK_DEV:="/dev/nbd0"}
: ${ALPINE_BRANCH:="v3.9"}
: ${ALPINE_MIRROR:="http://dl-cdn.alpinelinux.org/alpine"}
: ${ALPINE_PACKAGES:="build-base ca-certificates ssl_client"}
: ${ARCH:=}
: ${BIND_DIR:=}
: ${CHROOT_DIR:="/alpine-build-${ARCH}"}
: ${CHROOT_KEEP_VARS:="ARCH CI QEMU_EMULATOR CIRCLE_.* TRAVIS_.*"}
: ${EXTRA_REPOS:=}
: ${TEMP_DIR:=$(mktemp -d || echo /tmp/alpine)}

# Create Build Directory
if [ ! -d "${BUILD_DIR}" ]; then
	mkdir -p "${BUILD_DIR}"
fi

# Create Chroot Directory
if [ ! -d "${CHROOT_DIR}" ]; then
	mkdir -p "${CHROOT_DIR}"
fi

# Create Disk Image
qemu-img create -q -f qcow2 "${BUILD_DIR}/box.img" 32G

# Connect Disk Image
sudo qemu-nbd -c "${BLOCK_DEV}" "${BUILD_DIR}/box.img"

# Create Partition Table
sudo parted -msa opt "${BLOCK_DEV}" -- mklabel msdos

# Create Partition
sudo parted -msa opt "${BLOCK_DEV}" -- mkpart primary 1 -1

# Configure Partition
sudo parted -msa opt "${BLOCK_DEV}" -- set 1 boot on

# Formart Partition
sudo mkfs.xfs -q -L "RootFs" "${BLOCK_DEV}p1"

# Mount Partition
sudo mount "${BLOCK_DEV}p1" "${CHROOT_DIR}"

# Build Alpine Base Image
sudo \
  ALPINE_BRANCH="${ALPINE_BRANCH}" \
  ALPINE_MIRROR="${ALPINE_MIRROR}" \
  ALPINE_PACKAGES="${ALPINE_PACKAGES}" \
  ARCH="${ARCH}" \
  CHROOT_DIR="${CHROOT_DIR}" \
  CHROOT_KEEP_VARS="${CHROOT_KEEP_VARS}" \
  EXTRA_REPOS="${EXTRA_REPOS}" \
  ./alpine-chroot-install/alpine-chroot-install

# Install Boot Recode
"$CHROOT_DIR/enter-chroot" grub-install --target=i386-pc "${BLOCK_DEV}"

# Disconnect Disk Image
sudo sh -c "qemu-nbd -d ${BLOCK_DEV} > /dev/null"

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
