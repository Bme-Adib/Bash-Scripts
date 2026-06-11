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

* 🖥️ [Ubuntu Server Initial Setup (`server_setup.sh`)](#server-setup)
* 🐳 [Docker Manager & Installer (`manage_docker.sh`)](#docker-manager)
* ☁️ [Cloudflare Tunnel Auto-Setup (`setup_docker_cloudflare.sh`)](#cloudflare-tunnel)
* 📇 [Nginx Portfolio & Business Card Creator (`setup_docker_website_buisnessCard.sh`)](#portfolio-bizcard)
* 📂 [FileBrowser Quantum Container Setup (`setup_docker_filebrowser.sh`)](#filebrowser)
* 📓 [SiYuan Note Private Workspace Installer (`setup_docker_siyyuan.sh`)](#siyuan-note)
* 🔍 [Dozzle Real-time Log Viewer (`setup_docker_dozzle.sh`)](#dozzle-setup)
* 🗄️ [Postgres 16 & PostgREST API Setup (`setup_docker_postgres_postgrest.sh`)](#postgres-postgrest-setup)
* 📊 [Real-Time System Monitor (`monitor_system.sh`)](#system-monitor-setup)

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
   # (Note: server_setup.sh and manage_docker.sh require sudo)
   ```

---

<a id="server-setup"></a>
## 🖥️ Ubuntu Server Initial Setup (`server_setup.sh`)

### Description
An interactive, menu-driven post-installation script to configure, optimize, and secure fresh Ubuntu Servers. Before displaying the option menu, the script prints system statistics (OS name, Kernel, CPU model, BIOS version, RAM usage, and Partition storage info) to give you a quick health check of your system.

### How to Use
**One-Click Run (Recommended):**
```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/server_setup.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x server_setup.sh
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

<a id="docker-manager"></a>
## 🐳 Docker Manager & Installer (`manage_docker.sh`)

### Description
An interactive, menu-driven management utility for Docker. It provides a complete installer for Docker and Docker Compose V2 natively, and includes essential system diagnostics, daemon control, and space optimization tasks (pruning unused containers, volumes, and images).

### How to Use
**One-Click Run (Recommended):**
```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/manage_docker.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x manage_docker.sh
sudo ./manage_docker.sh
```

### Options & Inputs Inside the Script
* **`1) Install Docker & Docker Compose`**: Automatically installs Docker, components, GPG keys, and compose plugins. Prompts to add your non-root user to the `docker` group.
* **`2) Check Docker Service Status`**: Checks if the daemon is active and running, and outputs system configuration info.
* **`3) Show Docker Disk Space Usage`**: Displays a breakdown of disk space consumed by containers, images, and volumes.
* **`4) Stop All Running Containers`**: Gracefully stops all active containers on the server.
* **`5) Remove Unused Volumes (Volume Prune)`**: Cleans out orphan volumes not attached to any container.
* **`6) Remove Unused Images (Image Prune)`**: Prompts to prune dangling images (without tags) or all unused images.
* **`7) Remove Unused Volumes & Images`**: Performs a combined cleanup of both volumes and images.
* **`8) Deep Clean System (System Prune)`**: A complete purge of all stopped containers, networks, dangling/unused images, and local volumes.
* **`9) Restart Docker Daemon Service`**: Restarts the systemd Docker service daemon.

---

<a id="cloudflare-tunnel"></a>
## ☁️ Cloudflare Tunnel Auto-Setup (`setup_docker_cloudflare.sh`)

### Description
Generates and deploys a standalone Docker container running Cloudflare's `cloudflared` agent. This allows you to route external web traffic securely to your home server services via Cloudflare Tunnels without exposing ports on your home router or configuring dynamic DNS (DDNS).

### How to Use
**One-Click Run (Recommended):**
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/setup_docker_cloudflare.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x setup_docker_cloudflare.sh
./setup_docker_cloudflare.sh
```

### Options & Inputs Inside the Script
* **Cloudflare Tunnel Token**: Enter the secure tunnel token obtained from your Cloudflare Zero Trust Dashboard.
* **Docker Network Name**: Define the network name that `cloudflared` should join to reach other containers (defaults to `proxy-net`).
* **Target Network Creation**: If the network is missing on the host, the script prompts to automatically create it.
* **Deploy Confirmation**: Lets you review the generated `docker-compose.yml` and choose whether to deploy it immediately.

---

<a id="portfolio-bizcard"></a>
## 📇 Nginx Portfolio & Business Card Creator (`setup_docker_website_buisnessCard.sh`)

### Description
A template scaffolder that sets up folders, generates modern placeholder web pages, and writes a customized `docker-compose.yml` to serve a digital business card, a personal portfolio site, or both, running on Nginx.

> [!TIP]
> You can easily design a beautiful, responsive digital business card using **[EnBizCard](https://enbizcard.vishnuraghav.com/)**. Once generated and downloaded, extract and move the files directly into your project's `./biz` folder to replace the placeholder page!

### How to Use
**One-Click Run (Recommended):**
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/setup_docker_website_buisnessCard.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x setup_docker_website_buisnessCard.sh
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

<a id="filebrowser"></a>
## 📂 FileBrowser Quantum Container Setup (`setup_docker_filebrowser.sh`)

### Description
Spawns a highly configurable FileBrowser container allowing full-filesystem web management (`/` mapped to container `/srv`). Ideal for quick file transfers and management of configurations on your home server.

### How to Use
**One-Click Run (Recommended):**
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/setup_docker_filebrowser.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x setup_docker_filebrowser.sh
./setup_docker_filebrowser.sh
```

### Options & Inputs Inside the Script
* **Port Exposure**: Choose whether to expose the port directly to the host system. If yes, specify host port (defaults to `8081`). Checks if the port is in use.
* **Cloudflare Subdomain**: Enter the subdomain hostname (e.g., `files.example.com`) where the browser will be routed.
* **Cloudflare Network**: External network to attach the service container to (default `proxy-net`). Offers to create it if missing.
* **Admin Password**: Enter the initial password to secure the FileBrowser admin login account.
* **Deploy Confirmation**: Reviews settings and launches the docker compose stack.

---

<a id="siyuan-note"></a>
## 📓 SiYuan Note Private Workspace Installer (`setup_docker_siyyuan.sh`)

### Description
An automated setup utility for the privacy-focused, self-hosted note-taking application SiYuan. It sets up persistent directories and maps local UID/GID parameters to avoid file lock issues inside Docker.

### How to Use
**One-Click Run (Recommended):**
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/setup_docker_siyyuan.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x setup_docker_siyyuan.sh
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

<a id="dozzle-setup"></a>
## 🔍 Dozzle Real-time Log Viewer (`setup_docker_dozzle.sh`)

### Description
Spawns a Dozzle container to provide a beautiful, real-time web-based dashboard for viewing logs of all your running Docker containers.

### How to Use
**One-Click Run (Recommended):**
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/setup_docker_dozzle.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x setup_docker_dozzle.sh
./setup_docker_dozzle.sh
```

### Options & Inputs Inside the Script
* **Port Exposure**: Option to bind the Dozzle port (internal `8080`) to a host port (defaults to `8888`). Checks if the port is in use.
* **Cloudflare Subdomain**: Subdomain hostname (e.g. `logs.example.com`) for Zero Trust Routing.
* **Cloudflare Network**: Docker network name (default `proxy-net`) to connect Dozzle and cloudflared.
* **Deploy Confirmation**: Reviews compose file configuration and launches the Dozzle service.

---

<a id="postgres-postgrest-setup"></a>
## 🗄️ Postgres 16 & PostgREST API Setup (`setup_docker_postgres_postgrest.sh`)

### Description
Deploys a Postgres 16 database running on Alpine Linux alongside a PostgREST container. PostgREST automatically exposes your database tables, views, and functions directly as a RESTful web API. The setup script automatically creates the anonymous access database role (`anon`) and grants proper schema privileges to make configuration completely seamless.

### How to Use
**One-Click Run (Recommended):**
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/setup_docker_postgres_postgrest.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x setup_docker_postgres_postgrest.sh
./setup_docker_postgres_postgrest.sh
```

### Options & Inputs Inside the Script
* **Database Name**: The database schema to initialize (defaults to `app_db`).
* **Database Credentials**: Specify custom database owner username and password (generates a secure random 16-character password by default).
* **Database Port Exposure**: Option to bind the PostgreSQL port (`5432`) to the host. Checks if the port is in use.
* **PostgREST API Port Exposure**: Option to bind the PostgREST API port (`3000`) to the host (defaults to `3000`). Checks if the port is in use.
* **PostgREST Configuration**: Set custom API schema (default `public`) and anonymous db role (default `anon`).
* **Cloudflare Subdomain**: The subdomain (e.g., `api.example.com`) to route REST API traffic.
* **Cloudflare Network**: Docker network name (default `proxy-net`). Offers to create if missing.
* **Deploy Confirmation**: Reviews settings and launches both Postgres and PostgREST containers.

---

<a id="system-monitor-setup"></a>
## 📊 Real-Time System Monitor (`monitor_system.sh`)

### Description
Launches a gorgeous, real-time command-line resource monitor (`btop`) showing active CPU core speeds, RAM components, disk partitions, and active processes. The script automatically detects your system configuration and native package manager (apt, dnf, pacman, snap) to install `btop` if it's missing, falling back to compile-free static musl release binaries if required.

### How to Use
**One-Click Run (Recommended):**
```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/Bme-Adib/Bash-Scripts/refs/heads/main/monitor_system.sh)"
```
**Alternative (Manual Download):**
```bash
chmod +x monitor_system.sh
sudo ./monitor_system.sh
```

### Options & Inputs Inside the Script
- **Automatic Setup**: Verifies presence of `btop`, auto-updates packages, downloads binaries if missing, and configures files.
- **Diagnostics Dashboard**: Launches the monitor immediately upon successful validation or setup.

---

> [!NOTE]
> All scripts in this repository are formatted in the **Adib Builds Style** to ensure strict shell safety (`set -euo pipefail`), colorized diagnostic outputs, directory/file protection safeguards, and easy docker container management commands.
