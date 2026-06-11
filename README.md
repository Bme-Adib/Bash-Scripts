# 🛠️ Home Server Helper Bash Scripts by Adib Builds

[![YouTube](https://img.shields.io/badge/YouTube-@adibbuilds-red?style=for-the-badge&logo=youtube)](https://www.youtube.com/@adibbuilds)
[![Instagram](https://img.shields.io/badge/Instagram-@adibbuilds-purple?style=for-the-badge&logo=instagram)](https://www.instagram.com/adibbuilds)
[![Website](https://img.shields.io/badge/Website-adibbuilds.com-blue?style=for-the-badge)](https://adibbuilds.com)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue?style=for-the-badge&logo=docker)](https://www.docker.com)
[![Bash](https://img.shields.io/badge/Shell-Bash_5.0+-green?style=for-the-badge&logo=gnu-bash)](https://www.gnu.org/software/bash/)

Welcome! This repository contains a collection of interactive, robust, and automated bash helper scripts designed by **[Adib Builds](https://adibbuilds.com)**. These scripts aim to simplify home server management, automate initial Ubuntu Server hardening, and launch essential Docker applications and containers with zero hassle.

> [!TIP]
> You can also check the **[Adib Builds Downloads Page](https://adibbuilds.com/downloads)** to find all of these scripts with one-click copy options, making it incredibly easy to copy and run them directly on your server!

---

## 🌐 Connect With Adib Builds

Stay updated with new guides, tutorials, and scripts:
* 📺 **YouTube:** [Adib Builds Channel](https://www.youtube.com/@adibbuilds)
* 📸 **Instagram:** [@adibbuilds](https://www.instagram.com/adibbuilds)
* 🌐 **Website:** [adibbuilds.com](https://adibbuilds.com)
* 📇 **Digital Business Card:** [card.adibbuilds.com](https://card.adibbuilds.com)

---

## 🗺️ Table of Contents (Script Quick Links)

Click any of the scripts below to jump directly to its description, installation instructions, and configuration options:

* 🖥️ [Ubuntu Server Initial Setup (`server_setup.sh`)](#-ubuntu-server-initial-setup-server_setupsh)
* 🐳 [Docker & Compose Native Installer (`setup_docker.sh`)](#-docker--compose-native-installer-setup_dockersh)
* ☁️ [Cloudflare Tunnel Auto-Setup (`setup_docker_cloudflare.sh`)](#-cloudflare-tunnel-auto-setup-setup_docker_cloudflaresh)
* 📇 [Nginx Portfolio & Business Card Creator (`setup_docker_website_buisnessCard.sh`)](#-nginx-portfolio--business-card-creator-setup_docker_website_buisnesscardsh)
* 📂 [FileBrowser Quantum Container Setup (`setup_docker_filebrowser.sh`)](#-filebrowser-quantum-container-setup-setup_docker_filebrowsersh)
* 📓 [SiYuan Note Private Workspace Installer (`setup_docker_siyyuan.sh`)](#-siyuan-note-private-workspace-installer-setup_docker_siyyuansh)

---

## 📋 General Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Bme-Adib/Bash-Scripts.git
   cd Bash-Scripts
   ```
2. **Make any script executable:**
   ```bash
   chmod +x <script_name>.sh
   ```
3. **Execute:**
   ```bash
   ./<script_name>.sh
   # (Note: server_setup.sh and setup_docker.sh require sudo)
   ```

---

## 🖥️ Ubuntu Server Initial Setup (`server_setup.sh`)

### Description
An interactive, menu-driven post-installation script to configure, optimize, and secure fresh Ubuntu Servers. Before displaying the option menu, the script prints system statistics (OS name, Kernel, CPU model, BIOS version, RAM usage, and Partition storage info) to give you a quick health check of your system.

### How to Use
Run with root permissions (required to configure system services, users, and networks):
```bash
sudo ./server_setup.sh
```

### Options & Inputs Inside the Script
The script provides a choice menu with the following operations:
* **`1) Update and upgrade all packages`**: Updates the package index and runs a full upgrade.
* **`2) Attach Ubuntu Pro / ESM Token`**: Prompts for your Ubuntu Pro token to activate Extended Security Maintenance.
* **`3) Create Sudo User`**: Prompts for a username and password to create a new administrator account (with bash login shell) and offers to switch your active session to it immediately.
* **`4) Enable SSH & Add Authorized SSH Key`**: Verifies and installs OpenSSH if missing, enables the SSH daemon, and appends a custom SSH public key (e.g., `ssh-rsa ...`) to the specified user's `authorized_keys`.
* **`5) Enable Firewall (UFW) with port 22 open`**: Sets default rules (deny incoming, allow outgoing), opens port `22/tcp` for SSH, and forces UFW to enable.
* **`6) Assign Static IP Address (via Netplan)`**: Detects your active network interface and prompts for static IP/CIDR (e.g. `192.168.1.100/24`), default gateway, and DNS servers. Safely backs up existing configurations and generates a new Netplan file (`/etc/netplan/99-static-ip.yaml`).
* **`7) Configure Upstream DNS`**: Allows overriding `systemd-resolved` settings in `/etc/systemd/resolved.conf` with custom DNS list (default Google/Cloudflare).
* **`8) Enable NTP & Set Timezone`**: Enables network time sync and configures your system timezone (defaults to `Asia/Kuala_Lumpur`).
* **`9) Create Swap File & Optimize Swappiness`**: Evaluates system RAM, suggests a swap size, allocates a `/swapfile` (fallocate/dd fallback), configures permissions, enables the swap partition, adds it to `/etc/fstab` for persistence, and tunes swappiness to `10`.

---

## 🐳 Docker & Compose Native Installer (`setup_docker.sh`)

### Description
Installs the official Docker CE Engine, Docker CE CLI, Containerd, Docker Buildx, and Docker Compose V2 plugin natively. It handles adding keyrings, GPG keys, and apt repositories for Debian/Ubuntu based systems (with pop/mint mapping safety). If run on unsupported architectures/distributions, it automatically falls back to Docker's official convenience installation script.

### How to Use
Run with root permissions:
```bash
sudo ./setup_docker.sh
```

### Options & Inputs Inside the Script
* **Pre-Check Exits**: If Docker and Docker Compose are already present on the system, the script displays their versions and exits safely to prevent double-installation.
* **Proceed Confirmation**: Prompts for user confirmation before starting the package downloads (`y/n` default `y`).
* **Non-Root Group Access**: Automatically detects the standard user who invoked the script with `sudo` and prompts/adds them to the `docker` group so Docker commands can be run without prefixing `sudo`.

---

## ☁️ Cloudflare Tunnel Auto-Setup (`setup_docker_cloudflare.sh`)

### Description
Generates and deploys a standalone Docker container running Cloudflare's `cloudflared` agent. This allows you to route external web traffic securely to your home server services via Cloudflare Tunnels without exposing ports on your home router or configuring dynamic DNS (DDNS).

### How to Use
```bash
./setup_docker_cloudflare.sh
```

### Options & Inputs Inside the Script
* **Cloudflare Tunnel Token**: Enter the secure tunnel token obtained from your Cloudflare Zero Trust Dashboard.
* **Docker Network Name**: Define the network name that `cloudflared` should join to reach other containers (defaults to `proxy-net`).
* **Target Network Creation**: If the network is missing on the host, the script prompts to automatically create it.
* **Deploy Confirmation**: Lets you review the generated `docker-compose.yml` and choose whether to deploy it immediately.

---

## 📇 Nginx Portfolio & Business Card Creator (`setup_docker_website_buisnessCard.sh`)

### Description
A template scaffolder that sets up folders, generates modern placeholder web pages, and writes a customized `docker-compose.yml` to serve a digital business card, a personal portfolio site, or both, running on Nginx.

### How to Use
```bash
./setup_docker_website_buisnessCard.sh
```

### Options & Inputs Inside the Script
* **Project Name**: Scaffolds a project subdirectory using this name (defaults to `adib`, sanitized to lowercase/alphanumeric).
* **Project Type**: Selection list:
  1. *Business Card Only* (sets up one page on Nginx).
  2. *Website Only* (sets up one page on Nginx).
  3. *Business Card + Website* (runs two separate container instances).
* **Port exposure**: Enter custom host ports for binding (defaults to `8082` for biz card, `8083` for website). Checks if ports are already in use on the host system.
* **Docker Network**: Connects containers to a specified docker network (e.g. `proxy-net`). Inspects/creates it if it does not exist.
* **Deploy Confirmation**: Prints the finalized compose file configuration and prompts to launch the Nginx services.

---

## 📂 FileBrowser Quantum Container Setup (`setup_docker_filebrowser.sh`)

### Description
Spawns a highly configurable FileBrowser container allowing full-filesystem web management (`/` mapped to container `/srv`). Ideal for quick file transfers and management of configurations on your home server.

### How to Use
```bash
./setup_docker_filebrowser.sh
```

### Options & Inputs Inside the Script
* **Port Exposure**: Choose whether to expose the port directly to the host system. If yes, specify host port (defaults to `8081`). Checks if the port is in use.
* **Cloudflare Subdomain**: Enter the subdomain hostname (e.g., `files.example.com`) where the browser will be routed.
* **Cloudflare Network**: External network to attach the service container to (default `proxy-net`). Offers to create it if missing.
* **Admin Password**: Enter the initial password to secure the FileBrowser admin login account.
* **Deploy Confirmation**: Reviews settings and launches the docker compose stack.

---

## 📓 SiYuan Note Private Workspace Installer (`setup_docker_siyyuan.sh`)

### Description
An automated setup utility for the privacy-focused, self-hosted note-taking application SiYuan. It sets up persistent directories and maps local UID/GID parameters to avoid file lock issues inside Docker.

### How to Use
```bash
./setup_docker_siyyuan.sh
```

### Options & Inputs Inside the Script
* **Installation Directory**: Enter target path for deployment configuration and workspace (defaults to `./siyuan-workspace`).
* **Port**: Host port to bind to (defaults to `6806`). Checks if the port is already in use.
* **Access Authorization Code**: Set the login password (defaults to a randomly generated 12-character string).
* **Timezone**: Set container timezone (defaults to host system's timezone).
* **PUID / PGID**: Automatically detects your current user's UID and GID to run the service under matching permissions.
* **Deploy Confirmation**: Outputs compose file and deploys the container.

---

> [!NOTE]
> All scripts in this repository are formatted in the **Adib Builds Style** to ensure strict shell safety (`set -euo pipefail`), colorized diagnostic outputs, directory/file protection safeguards, and easy docker container management commands.
