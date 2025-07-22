#!/bin/bash

# BullOS Builder for Raspberry Pi 5
# Version 2.0
# Maintains image under 2GB with proper splash screen and console display

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
IMAGE_SIZE=1900  # MB - under 2GB requirement

# Create directories
mkdir -p ${WORK_DIR} ${OUTPUT_DIR}

# Clean previous build
sudo rm -rf ${WORK_DIR}/rootfs ${WORK_DIR}/linux ${WORK_DIR}/boot ${WORK_DIR}/root

# Step 1: Get minimal Debian system
echo "[1/8] Creating minimal Debian rootfs..."
sudo debootstrap --arch=${TARGET_ARCH} --variant=minbase stable ${WORK_DIR}/rootfs http://deb.debian.org/debian/

# Step 2: Install essential packages
echo "[2/8] Installing essential packages..."
cat << EOF | sudo chroot ${WORK_DIR}/rootfs /bin/bash
apt-get update
apt-get install -y --no-install-recommends \
    sudo systemd systemd-sysv initramfs-tools \
    plymouth plymouth-themes plymouth-x11 \
    console-setup keyboard-configuration locales \
    git build-essential bc bison flex libssl-dev \
    kmod cpio libncurses5-dev crossbuild-essential-arm64 \
    u-boot-tools device-tree-compiler \
    raspi-firmware raspi-config
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Step 3: Build optimized kernel
echo "[3/8] Building Raspberry Pi 5 kernel..."
if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
    echo "Installing cross-compiler..."
    sudo apt-get update
    sudo apt-get install -y gcc-aarch64-linux-gnu
fi

if [ ! -d "${WORK_DIR}/linux" ]; then
    git clone --depth=1 --branch ${KERNEL_BRANCH} ${KERNEL_SOURCE} ${WORK_DIR}/linux
fi

cd ${WORK_DIR}/linux
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig

# Optimize kernel for size
scripts/config --disable DEBUG_INFO
scripts/config --disable DEBUG_KERNEL
scripts/config --set-val CONFIG_CC_OPTIMIZE_FOR_SIZE y

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
cd -

# Step 4: Install kernel and firmware
echo "[4/8] Installing kernel and firmware..."
sudo mkdir -p ${WORK_DIR}/rootfs/boot
sudo cp ${WORK_DIR}/linux/arch/arm64/boot/Image ${WORK_DIR}/rootfs/boot/kernel8.img
sudo cp ${WORK_DIR}/linux/arch/arm64/boot/dts/broadcom/*.dtb ${WORK_DIR}/rootfs/boot/
sudo cp -rL ${WORK_DIR}/linux/arch/arm64/boot/dts/overlays ${WORK_DIR}/rootfs/boot/

# Step 5: Customize OS branding and splash
echo "[5/8] Setting up branding and splash screen..."

# Create custom Plymouth theme
sudo mkdir -p ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos
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
wallpaper_image = Image("bullos-splash.gif");
background_color = (1.0, 1.0, 1.0);  # White background

bullos_logo = Image("bullos-logo.png");
bullos_logo_sprite = Sprite(bullos_logo);
bullos_logo_sprite.SetX(Window.GetWidth()/2 - bullos_logo.GetWidth()/2);
bullos_logo_sprite.SetY(Window.GetHeight()/2 - bullos_logo.GetHeight()/2);

progress_bar = Box(Window.GetWidth()/4, Window.GetHeight()*3/4, Window.GetWidth()/2, 5);
progress_bar.SetColor(0.16, 0.63, 0.96, 1.0);  # Blue progress bar
progress_sprite = Sprite(progress_bar);
progress_sprite.SetX(Window.GetWidth()/4);
progress_sprite.SetY(Window.GetHeight()*3/4);
EOF

# Copy branding assets
sudo cp ${LOGO_1TO1_PATH} ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos-logo.png
sudo cp ${SPLASH_GIF_PATH} ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos-splash.gif

# Set Plymouth theme
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "plymouth-set-default-theme -R bullos"

# OS branding
sudo tee ${WORK_DIR}/rootfs/etc/os-release >/dev/null <<EOF
PRETTY_NAME="${OS_NAME} ${OS_VERSION}"
NAME="${OS_NAME}"
VERSION="${OS_VERSION}"
ID=bullos
ID_LIKE=debian
HOME_URL="https://bullos.example.com"
SUPPORT_URL="https://support.bullos.example.com"
BUG_REPORT_URL="https://bugs.bullos.example.com"
EOF

sudo sed -i 's/Raspberry Pi/BullOS/g' ${WORK_DIR}/rootfs/etc/issue
sudo sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${OS_NAME} ${OS_VERSION}\"/" ${WORK_DIR}/rootfs/usr/lib/os-release

# Step 6: Configure system services and console
echo "[6/8] Configuring system services and console..."

# Enable Plymouth
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "systemctl enable plymouth-start"

# Fix console display
sudo tee ${WORK_DIR}/rootfs/etc/default/console-setup >/dev/null <<EOF
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Fixed"
FONTSIZE="16"
VIDEOMODE=
EOF

# Set up locales
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "locale-gen"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "update-locale LANG=en_US.UTF-8"

# Create user
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "echo 'root:bullos' | chpasswd"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "useradd -m -G sudo -s /bin/bash bullos"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "echo 'bullos:bullos' | chpasswd"

# Step 7: Create optimized image
echo "[7/8] Creating image file (under 2GB)..."
IMAGE_FILE="${OUTPUT_DIR}/bullos-rpi5-${OS_VERSION}.img"

# Create blank image
dd if=/dev/zero of=${IMAGE_FILE} bs=1M count=${IMAGE_SIZE}
LOOP_DEVICE=$(sudo losetup -f --show ${IMAGE_FILE})

# Partition and format
sudo parted -s ${LOOP_DEVICE} mklabel msdos
sudo parted -s ${LOOP_DEVICE} mkpart primary fat32 1MiB 256MiB
sudo parted -s ${LOOP_DEVICE} set 1 boot on
sudo parted -s ${LOOP_DEVICE} mkpart primary ext4 256MiB 100%

sudo mkfs.vfat -F32 -n BOOT ${LOOP_DEVICE}p1
sudo mkfs.ext4 -L ROOTFS -O ^metadata_csum,^64bit ${LOOP_DEVICE}p2

# Mount partitions
mkdir -p ${WORK_DIR}/boot ${WORK_DIR}/root
sudo mount ${LOOP_DEVICE}p1 ${WORK_DIR}/boot
sudo mount ${LOOP_DEVICE}p2 ${WORK_DIR}/root

# Copy rootfs
sudo cp -a ${WORK_DIR}/rootfs/. ${WORK_DIR}/root/
sudo cp -rL ${WORK_DIR}/rootfs/boot/. ${WORK_DIR}/boot/

# Create boot files
cat << EOF | sudo tee ${WORK_DIR}/boot/config.txt >/dev/null
# BullOS Configuration
arm_64bit=1
kernel=kernel8.img
gpu_mem=128
disable_overscan=1
dtoverlay=vc4-kms-v3d
max_framebuffers=2
disable_splash=0
boot_delay=1
EOF

cat << EOF | sudo tee ${WORK_DIR}/boot/cmdline.txt >/dev/null
console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet splash plymouth.ignore-serial-consoles loglevel=3 vt.global_cursor_default=0
EOF

# Clean up
sudo umount ${WORK_DIR}/boot ${WORK_DIR}/root
sudo losetup -d ${LOOP_DEVICE}
rm -rf ${WORK_DIR}/boot ${WORK_DIR}/root

# Step 8: Finalize image
echo "[8/8] Finalizing image..."
# Truncate to actual size
sudo truncate -s $(du -s ${IMAGE_FILE} | cut -f1) ${IMAGE_FILE}

# Compress image
echo "Compressing image..."
xz -9 -T0 ${IMAGE_FILE}

echo "------------------------------------------------------------"
echo "Build complete! Image is available at: ${IMAGE_FILE}.xz"
echo "Size: $(du -h ${IMAGE_FILE}.xz | cut -f1)"
echo "------------------------------------------------------------"#!/bin/bash

# BullOS Builder for Raspberry Pi 5
# Version 2.0
# Maintains image under 2GB with proper splash screen and console display

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
IMAGE_SIZE=1900  # MB - under 2GB requirement

# Create directories
mkdir -p ${WORK_DIR} ${OUTPUT_DIR}

# Clean previous build
sudo rm -rf ${WORK_DIR}/rootfs ${WORK_DIR}/linux ${WORK_DIR}/boot ${WORK_DIR}/root

# Step 1: Get minimal Debian system
echo "[1/8] Creating minimal Debian rootfs..."
sudo debootstrap --arch=${TARGET_ARCH} --variant=minbase stable ${WORK_DIR}/rootfs http://deb.debian.org/debian/

# Step 2: Install essential packages
echo "[2/8] Installing essential packages..."
cat << EOF | sudo chroot ${WORK_DIR}/rootfs /bin/bash
apt-get update
apt-get install -y --no-install-recommends \
    sudo systemd systemd-sysv initramfs-tools \
    plymouth plymouth-themes plymouth-x11 \
    console-setup keyboard-configuration locales \
    git build-essential bc bison flex libssl-dev \
    kmod cpio libncurses5-dev crossbuild-essential-arm64 \
    u-boot-tools device-tree-compiler \
    raspi-firmware raspi-config
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Step 3: Build optimized kernel
echo "[3/8] Building Raspberry Pi 5 kernel..."
if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
    echo "Installing cross-compiler..."
    sudo apt-get update
    sudo apt-get install -y gcc-aarch64-linux-gnu
fi

if [ ! -d "${WORK_DIR}/linux" ]; then
    git clone --depth=1 --branch ${KERNEL_BRANCH} ${KERNEL_SOURCE} ${WORK_DIR}/linux
fi

cd ${WORK_DIR}/linux
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig

# Optimize kernel for size
scripts/config --disable DEBUG_INFO
scripts/config --disable DEBUG_KERNEL
scripts/config --set-val CONFIG_CC_OPTIMIZE_FOR_SIZE y

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
cd -

# Step 4: Install kernel and firmware
echo "[4/8] Installing kernel and firmware..."
sudo mkdir -p ${WORK_DIR}/rootfs/boot
sudo cp ${WORK_DIR}/linux/arch/arm64/boot/Image ${WORK_DIR}/rootfs/boot/kernel8.img
sudo cp ${WORK_DIR}/linux/arch/arm64/boot/dts/broadcom/*.dtb ${WORK_DIR}/rootfs/boot/
sudo cp -rL ${WORK_DIR}/linux/arch/arm64/boot/dts/overlays ${WORK_DIR}/rootfs/boot/

# Step 5: Customize OS branding and splash
echo "[5/8] Setting up branding and splash screen..."

# Create custom Plymouth theme
sudo mkdir -p ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos
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
wallpaper_image = Image("bullos-splash.gif");
background_color = (1.0, 1.0, 1.0);  # White background

bullos_logo = Image("bullos-logo.png");
bullos_logo_sprite = Sprite(bullos_logo);
bullos_logo_sprite.SetX(Window.GetWidth()/2 - bullos_logo.GetWidth()/2);
bullos_logo_sprite.SetY(Window.GetHeight()/2 - bullos_logo.GetHeight()/2);

progress_bar = Box(Window.GetWidth()/4, Window.GetHeight()*3/4, Window.GetWidth()/2, 5);
progress_bar.SetColor(0.16, 0.63, 0.96, 1.0);  # Blue progress bar
progress_sprite = Sprite(progress_bar);
progress_sprite.SetX(Window.GetWidth()/4);
progress_sprite.SetY(Window.GetHeight()*3/4);
EOF

# Copy branding assets
sudo cp ${LOGO_1TO1_PATH} ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos-logo.png
sudo cp ${SPLASH_GIF_PATH} ${WORK_DIR}/rootfs/usr/share/plymouth/themes/bullos/bullos-splash.gif

# Set Plymouth theme
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "plymouth-set-default-theme -R bullos"

# OS branding
sudo tee ${WORK_DIR}/rootfs/etc/os-release >/dev/null <<EOF
PRETTY_NAME="${OS_NAME} ${OS_VERSION}"
NAME="${OS_NAME}"
VERSION="${OS_VERSION}"
ID=bullos
ID_LIKE=debian
HOME_URL="https://bullos.example.com"
SUPPORT_URL="https://support.bullos.example.com"
BUG_REPORT_URL="https://bugs.bullos.example.com"
EOF

sudo sed -i 's/Raspberry Pi/BullOS/g' ${WORK_DIR}/rootfs/etc/issue
sudo sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${OS_NAME} ${OS_VERSION}\"/" ${WORK_DIR}/rootfs/usr/lib/os-release

# Step 6: Configure system services and console
echo "[6/8] Configuring system services and console..."

# Enable Plymouth
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "systemctl enable plymouth-start"

# Fix console display
sudo tee ${WORK_DIR}/rootfs/etc/default/console-setup >/dev/null <<EOF
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Fixed"
FONTSIZE="16"
VIDEOMODE=
EOF

# Set up locales
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "locale-gen"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "update-locale LANG=en_US.UTF-8"

# Create user
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "echo 'root:bullos' | chpasswd"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "useradd -m -G sudo -s /bin/bash bullos"
sudo chroot ${WORK_DIR}/rootfs /bin/bash -c "echo 'bullos:bullos' | chpasswd"

# Step 7: Create optimized image
echo "[7/8] Creating image file (under 2GB)..."
IMAGE_FILE="${OUTPUT_DIR}/bullos-rpi5-${OS_VERSION}.img"

# Create blank image
dd if=/dev/zero of=${IMAGE_FILE} bs=1M count=${IMAGE_SIZE}
LOOP_DEVICE=$(sudo losetup -f --show ${IMAGE_FILE})

# Partition and format
sudo parted -s ${LOOP_DEVICE} mklabel msdos
sudo parted -s ${LOOP_DEVICE} mkpart primary fat32 1MiB 256MiB
sudo parted -s ${LOOP_DEVICE} set 1 boot on
sudo parted -s ${LOOP_DEVICE} mkpart primary ext4 256MiB 100%

sudo mkfs.vfat -F32 -n BOOT ${LOOP_DEVICE}p1
sudo mkfs.ext4 -L ROOTFS -O ^metadata_csum,^64bit ${LOOP_DEVICE}p2

# Mount partitions
mkdir -p ${WORK_DIR}/boot ${WORK_DIR}/root
sudo mount ${LOOP_DEVICE}p1 ${WORK_DIR}/boot
sudo mount ${LOOP_DEVICE}p2 ${WORK_DIR}/root

# Copy rootfs
sudo cp -a ${WORK_DIR}/rootfs/. ${WORK_DIR}/root/
sudo cp -rL ${WORK_DIR}/rootfs/boot/. ${WORK_DIR}/boot/

# Create boot files
cat << EOF | sudo tee ${WORK_DIR}/boot/config.txt >/dev/null
# BullOS Configuration
arm_64bit=1
kernel=kernel8.img
gpu_mem=128
disable_overscan=1
dtoverlay=vc4-kms-v3d
max_framebuffers=2
disable_splash=0
boot_delay=1
EOF

cat << EOF | sudo tee ${WORK_DIR}/boot/cmdline.txt >/dev/null
console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet splash plymouth.ignore-serial-consoles loglevel=3 vt.global_cursor_default=0
EOF

# Clean up
sudo umount ${WORK_DIR}/boot ${WORK_DIR}/root
sudo losetup -d ${LOOP_DEVICE}
rm -rf ${WORK_DIR}/boot ${WORK_DIR}/root

# Step 8: Finalize image
echo "[8/8] Finalizing image..."
# Truncate to actual size
sudo truncate -s $(du -s ${IMAGE_FILE} | cut -f1) ${IMAGE_FILE}

# Compress image
echo "Compressing image..."
xz -9 -T0 ${IMAGE_FILE}

echo "------------------------------------------------------------"
echo "Build complete! Image is available at: ${IMAGE_FILE}.xz"
echo "Size: $(du -h ${IMAGE_FILE}.xz | cut -f1)"
echo "------------------------------------------------------------"