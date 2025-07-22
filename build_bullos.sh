#!/bin/bash

# BullOS Builder for Raspberry Pi 5
# Version 1.3

set -e

# Configuration
OS_NAME="BullOS"
OS_VERSION="1.0"
TARGET_ARCH="arm64"
WORK_DIR="./bullos-build"
OUTPUT_DIR="./output"
LOGO_1TO1_PATH="./logo/logo.png"
SPLASH_GIF_PATH="./logo/splash.gif"
KERNEL_SOURCE="https://github.com/raspberrypi/linux"
KERNEL_BRANCH="rpi-6.6.y"
IMAGE_SIZE=4000 # in MB

# Create directories
mkdir -p ${WORK_DIR} ${OUTPUT_DIR}

# Step 1: Get base Debian system
echo "[1/8] Getting base Debian system..."
if [ ! -d "${WORK_DIR}/rootfs" ]; then
    sudo debootstrap --arch=${TARGET_ARCH} --variant=minbase stable ${WORK_DIR}/rootfs http://deb.debian.org/debian/
fi

# Step 2: Install required packages in chroot
echo "[2/8] Installing required packages..."
cat << EOF | sudo chroot ${WORK_DIR}/rootfs /bin/bash
apt-get update
apt-get install -y --no-install-recommends \
    sudo systemd network-manager \
    plymouth plymouth-themes console-setup keyboard-configuration \
    git build-essential bc bison flex libssl-dev \
    kmod cpio libncurses5-dev crossbuild-essential-arm64 \
    u-boot-tools device-tree-compiler
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Step 3: Build custom kernel
echo "[3/8] Building custom kernel..."
if [ ! -d "${WORK_DIR}/linux" ]; then
    git clone --depth=1 --branch ${KERNEL_BRANCH} ${KERNEL_SOURCE} ${WORK_DIR}/linux
fi

if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
    echo "Installing cross-compiler..."
    sudo apt-get update
    sudo apt-get install -y gcc-aarch64-linux-gnu
fi

cd ${WORK_DIR}/linux
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
cd -

# Step 4: Install kernel to rootfs
echo "[4/8] Installing kernel..."
sudo mkdir -p ${WORK_DIR}/rootfs/boot
sudo cp ${WORK_DIR}/linux/arch/arm64/boot/Image ${WORK_DIR}/rootfs/boot/kernel8.img
sudo cp ${WORK_DIR}/linux/arch/arm64/boot/dts/broadcom/*.dtb ${WORK_DIR}/rootfs/boot/
sudo cp -rL ${WORK_DIR}/linux/arch/arm64/boot/dts/overlays ${WORK_DIR}/rootfs/boot/

# Step 5: Customize OS branding
echo "[5/8] Customizing OS branding..."

# Create Plymouth theme directory
sudo mkdir -p ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos

# Create theme files
cat << EOF | sudo tee ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos.plymouth >/dev/null
[Plymouth Theme]
Name=BullOS Splash
Description=A custom splash screen for BullOS
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/bullos
ScriptFile=/usr/share/plymouth/themes/bullos/bullos.script
EOF

cat << EOF | sudo tee ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos.script >/dev/null
wallpaper_image=Image("bullos-splash.gif");

bullos_logo = Image("bullos-logo.png");
bullos_logo_sprite = Sprite(bullos_logo);
bullos_logo_sprite.SetX(Window.GetWidth()/2 - bullos_logo.GetWidth()/2);
bullos_logo_sprite.SetY(Window.GetHeight()/2 - bullos_logo.GetHeight()/2);

progress_bar = Box(Window.GetWidth()/4, Window.GetHeight()*3/4, Window.GetWidth()/2, 5);
progress_bar.SetColor(0.16, 0.63, 0.96, 1.0);
progress_sprite = Sprite(progress_bar);
progress_sprite.SetX(Window.GetWidth()/4);
progress_sprite.SetY(Window.GetHeight()*3/4);
EOF

# Copy branding files
sudo mkdir -p ${WORK_DIR}/rootfs/usr/share/pixmaps
sudo cp ${LOGO_1TO1_PATH} ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos-logo.png
sudo cp ${LOGO_1TO1_PATH} ${WORK_DIR}/rootfs/usr/share/pixmaps/bullos-logo.png
sudo cp ${SPLASH_GIF_PATH} ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos-splash.gif

# Update OS information
sudo sed -i 's/Raspberry Pi/BullOS/g' ${WORK_DIR}/rootfs/etc/os-release
sudo sed -i 's/Debian/BullOS/g' ${WORK_DIR}/rootfs/etc/os-release
sudo sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${OS_NAME} ${OS_VERSION}\"/" ${WORK_DIR}/rootfs/etc/os-release

# Step 6: Create user and set up environment
echo "[6/8] Setting up user environment..."
cat << EOF | sudo chroot ${WORK_DIR}/rootfs /bin/bash
echo "root:bullos" | chpasswd
useradd -m -G sudo -s /bin/bash bullos
echo "bullos:bullos" | chpasswd
echo "${OS_NAME} ${OS_VERSION} \\n \\l" > /etc/issue
EOF

# Set Plymouth theme (must be done after all files are created)
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "plymouth-set-default-theme -R bullos"

# Step 7: Prepare image file
echo "[7/8] Creating image file..."
IMAGE_FILE="${OUTPUT_DIR}/bullos-rpi5-${OS_VERSION}.img"

dd if=/dev/zero of=${IMAGE_FILE} bs=1M count=${IMAGE_SIZE}
LOOP_DEVICE=$(sudo losetup -f --show ${IMAGE_FILE})

sudo parted -s ${LOOP_DEVICE} mklabel msdos
sudo parted -s ${LOOP_DEVICE} mkpart primary fat32 1MiB 256MiB
sudo parted -s ${LOOP_DEVICE} mkpart primary ext4 256MiB 100%
sudo mkfs.vfat -F32 ${LOOP_DEVICE}p1
sudo mkfs.ext4 ${LOOP_DEVICE}p2

mkdir -p ${WORK_DIR}/boot ${WORK_DIR}/root
sudo mount ${LOOP_DEVICE}p1 ${WORK_DIR}/boot
sudo mount ${LOOP_DEVICE}p2 ${WORK_DIR}/root

sudo cp -a ${WORK_DIR}/rootfs/. ${WORK_DIR}/root/
sudo cp -rL ${WORK_DIR}/rootfs/boot/. ${WORK_DIR}/boot/

cat << EOF | sudo tee ${WORK_DIR}/boot/config.txt >/dev/null
arm_64bit=1
kernel=kernel8.img
gpu_mem=256
disable_overscan=1
dtoverlay=vc4-kms-v3d
max_framebuffers=2
EOF

cat << EOF | sudo tee ${WORK_DIR}/boot/cmdline.txt >/dev/null
console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet splash plymouth.ignore-serial-consoles
EOF

sudo umount ${WORK_DIR}/boot ${WORK_DIR}/root
sudo losetup -d ${LOOP_DEVICE}
rm -rf ${WORK_DIR}/boot ${WORK_DIR}/root

# Step 8: Compress image
echo "[8/8] Compressing image..."
xz -9 -T0 ${IMAGE_FILE}

echo "Build complete! Image is available at: ${IMAGE_FILE}.xz"