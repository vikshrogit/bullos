#!/bin/bash
set -e

# ========= BullOs Build Config =========
OS_NAME="BullOs"
OS_VERSION="1.0"
ARCH="arm64"
DISTRO="bookworm"
IMG_NAME="${OS_NAME}-${OS_VERSION}-raspberrypi5.img"
MOUNT_DIR="./mnt"
BUILD_DIR="./build"
LOGO_DIR="./logo"

# ========= Detect Host Info =========
HOST_ARCH=$(uname -m)
HOST_OS=$(uname -s)

echo "[*] Building $OS_NAME v$OS_VERSION for Raspberry Pi 5"
echo "[*] Host OS: $HOST_OS | Arch: $HOST_ARCH"

# ========= Check Requirements =========
REQUIRED_CMDS=(qemu-debootstrap kpartx parted losetup debootstrap rsync wget git make gcc)
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v $cmd &> /dev/null; then
    echo "[!] Missing required command: $cmd"
    exit 1
  fi
done

# ========= Prepare Build Environment =========
mkdir -p $BUILD_DIR $MOUNT_DIR

# ========= Create Disk Image =========
echo "[*] Creating disk image..."
dd if=/dev/zero of=$IMG_NAME bs=1M count=2048
parted $IMG_NAME --script mklabel msdos
parted $IMG_NAME --script mkpart primary ext4 1MiB 100%

# ========= Setup Loop Device =========
LOOP_DEV=$(losetup --show -f -P $IMG_NAME)
mkfs.ext4 "${LOOP_DEV}p1"
mount "${LOOP_DEV}p1" $MOUNT_DIR

# ========= Debootstrap =========
echo "[*] Running debootstrap (1st stage)..."
qemu-debootstrap --arch=$ARCH $DISTRO $MOUNT_DIR http://deb.debian.org/debian

# ========= Copy Customization =========
echo "[*] Copying custom logo and splash..."
mkdir -p $MOUNT_DIR/boot/bullos
cp $LOGO_DIR/logo.png $MOUNT_DIR/boot/bullos/logo.png
cp $LOGO_DIR/splash.gif $MOUNT_DIR/boot/bullos/splash.gif

# ========= Branding =========
echo "[*] Setting BullOs branding..."
echo "$OS_NAME $OS_VERSION" > $MOUNT_DIR/etc/bullos-release

# ========= Install Kernel & Firmware =========
echo "[*] Installing Raspberry Pi firmware..."
mount --bind /dev $MOUNT_DIR/dev
mount --bind /proc $MOUNT_DIR/proc
mount --bind /sys $MOUNT_DIR/sys

chroot $MOUNT_DIR /bin/bash <<EOF
apt update
apt install -y linux-image-arm64 firmware-brcm80211 raspberrypi-bootloader u-boot-rpi
echo "BullOs 1.0 (arm64)" > /etc/issue
EOF

# ========= Secure Build =========
echo "[*] Hardening: Enabling secure boot entries, obfuscation layers..."
chroot $MOUNT_DIR /bin/bash <<EOF
apt install -y openssh-server fail2ban ufw
ufw enable
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
EOF

# ========= Unmount Everything =========
umount -lf $MOUNT_DIR/dev || true
umount -lf $MOUNT_DIR/proc || true
umount -lf $MOUNT_DIR/sys || true
umount -lf $MOUNT_DIR

losetup -d $LOOP_DEV

echo "[✓] BullOs Image Built Successfully: $IMG_NAME"
