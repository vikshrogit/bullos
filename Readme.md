<p align="center">
  <img src="logo/logo.png" width="200" alt="BullOs Logo"/>
</p>

<h1 align="center">🐂 BullOs v1.0</h1>
<h3 align="center">A Custom Debian-based OS for Raspberry Pi 5 — Fast, Secure & Fully Yours!</h3>

<p align="center">
  <img src="logo/splash.gif" width="400" alt="BullOs Splash"/>
</p>

---

## 🚀 Overview

**BullOs** is a lightning-fast, security-hardened, fully customizable OS built specifically for the **Raspberry Pi 5**. Based on **Debian 12 (Bookworm)** and tailored with your branding, logos, and boot splash — it's your OS, your rules. 🔐✨

> 💡 Build it once. Control it forever. No more limits.

---

## 🛠️ Features

- ✅ Based on **Debian 12 (Bookworm)**
- 🧠 Custom kernel for **Raspberry Pi 5 (ARM64)**
- 🎨 **Custom logo** & **splash screen**
- 🔐 Security hardened (SSH locked, UFW, fail2ban preinstalled)
- ⚡ Fully Automated Build Script (`build-bullos.sh`)
- 📦 Lightweight with only essential packages
- 🧩 Easily extensible & OTA-ready

---

## 💻 Target: Raspberry Pi 5

| Feature           | Support |
|-------------------|---------|
| CPU: ARM Cortex-A76 | ✅ Yes |
| RAM: 4GB / 8GB     | ✅ Yes |
| GPU Acceleration   | ✅ Optional |
| Wi-Fi + Bluetooth  | ✅ Yes |
| GPIO, SPI, I2C     | ✅ Yes |
| Secure Boot        | 🔒 Partial (configurable) |

---

## 🧰 Requirements (Host System)

| Requirement      | Minimum             | Recommended       |
|------------------|---------------------|-------------------|
| OS               | Ubuntu / Debian     | Ubuntu 22.04+     |
| Architecture     | x86_64 (64-bit)     | ✅ Required       |
| RAM              | 4 GB                | 8–16 GB           |
| Disk Space       | 10 GB               | 20–40 GB          |
| Internet         | ✅ Required         | Fast preferred    |

### 🔧 Required Tools
```bash
sudo apt install -y qemu-user-static debootstrap parted losetup kpartx rsync wget git make gcc
````

---

## 🔃 Folder Structure

```
project-root/
├── build-bullos.sh       # 🐚 Auto-build script for pipeline
├── bullos.sh       # 🐚 Auto-build script for user
├── BullOs-1.0-raspberrypi5.img  # 🧱 Output image (after build)
├── logo/
│   ├── logo.png   # 🖼️ Custom boot logo
│   └── splash.gif        # 🎞️ Splash screen
```

---

## 🔨 How to Build

```bash
git clone https://github.com/yourusername/bullos.git
cd bullos
chmod +x bullos.sh
./build-bullos.sh
```

✅ This will produce:

```
BullOs-1.0-raspberrypi5.img
```

Flash this image using Balena Etcher or `dd`:

```bash
sudo dd if=BullOs-1.0-raspberrypi5.img of=/dev/sdX bs=4M status=progress
```

---

## 🔐 Security Add-ons

* 🔒 UFW firewall pre-configured
* 🚫 SSH root login disabled
* 📜 Fail2Ban for brute-force protection
* ✅ Minimal attack surface (optional: AppArmor, custom bootloader keys)

---

## 💡 Future Roadmap

* [ ] Live GUI with LXQt or XFCE
* [ ] Encrypted partitions & secure boot
* [ ] OTA Updater module
* [ ] Flatpak/Snap preconfigured support
* [ ] Web-based installer and dashboard

---

## 📜 License

```
Copyright (c) 2025 VIKSHRO

Licensed under the MIT License. See LICENSE file for details.
```

---

<p align="center">
  <img src="logo/logo.png" width="100"/><br/>
  <b>BullOs — Your OS. Your Logic. Your Control. 🐂</b>
</p>
