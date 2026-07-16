# 🛠️ Home Server Helper Bash Scripts by Ghannams Academy
 
[![YouTube](https://img.shields.io/badge/YouTube-@ghannamsAcademy-red?style=for-the-badge&logo=youtube)](https://www.youtube.com/@ghannamsAcademy)
[![Instagram](https://img.shields.io/badge/Instagram-@ghannamsAcademy-purple?style=for-the-badge&logo=instagram)](https://www.instagram.com/ghannamsAcademy)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue?style=for-the-badge&logo=docker)](https://www.docker.com)
[![Bash](https://img.shields.io/badge/Shell-Bash_5.0+-green?style=for-the-badge&logo=gnu-bash)](https://www.gnu.org/software/bash/)

Welcome! This repository is a collection of interactive, color-coded, and highly secure automation helper scripts built by **Ghannams Academy**. 

If you've ever wanted to turn an old laptop gathering dust in your closet, or a cheap $4/month virtual server, into your own secure private home cloud, **you are in the right place!** These scripts do all the heavy lifting—from securing your system to installing web apps—with zero prior coding knowledge required.

---

## 📖 Self-Hosting & Server Concepts Explained in Plain English

Before diving in, let’s demystify some of the terms you will see in server tutorials:

* **Self-Hosting**: Running software applications on your own hardware (like an old PC or a VPS) instead of paying subscription fees to Google, Dropbox, YNAB, or Notion. You own your data.
* **Server (Host)**: Any computer that remains turned on 24/7, connected to the internet, waiting to serve files or apps to you.
* **VPS (Virtual Private Server)**: A computer rented in the cloud (on Hetzner, DigitalOcean, Linode) that runs 24/7 and gives you your own dedicated internet address (IP).
* **Docker**: Think of Docker as a "virtual shipping container." Instead of installing software directly onto your server (which can cause messy conflicts), Docker isolates each app inside its own container. It runs cleanly on any server.
* **Docker Compose**: The "recipe file" (`docker-compose.yml`) that tells Docker exactly how to build, link, and run your apps together.
* **Port**: Think of your server's IP address as the building address, and a port as the apartment number. If your server is at `192.168.1.100`, your dashboard app might live in apartment `8080` (accessible at `http://192.168.1.100:8080`).
* **Reverse Proxy / Cloudflare Tunnel**: Traditionally, to access your home server from outside your house, you had to open holes in your home router (called "Port Forwarding"), which is a major security risk. A tunnel creates a secure outbound bridge from your server to Cloudflare, letting you access your apps using web domains (e.g. `mybudget.example.com`) without exposing your home network.

---

## 🚀 Beginner's Quick Start Guide

### Step 1: Access Your Server
To run these scripts, you need to open your server's command-line prompt.
* **If you rent a VPS**: Open your computer's terminal (or download a free tool like **Termius** or **PuTTY**), and type:
  ```bash
  ssh root@your_server_ip
  ```
* **If you have a local Ubuntu Server**: Log in directly using the keyboard connected to the server.

### Step 2: Run a Script (One-Click Command)
You don't need to download Git or clone files. You can execute any script directly by copy-pasting the **One-Click Run** command in each app section below. 

For example, to check your system's hardware specs and monitor performance in real-time, copy and paste this command and hit `[ENTER]`:
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/system_monitor.sh)"
```

### Step 3: Fill Out the Prompts
Every script in this repository is interactive. It will ask you simple questions (like "Enter a port number" or "Do you want to run this now?").
* The script always suggests safe **default choices** inside brackets, like `[y]` or `[5006]`.
* If you are unsure, simply press `[ENTER]` to accept the default!

---

## 🗺️ Index of Scripts & One-Click Installs

Click any script to jump directly to its explanation and copy-paste installer:

* [🚀 All-in-One VPS & Laptop Server Config (`configure_new_server.sh`)](#server-config)
* [🖥️ Ubuntu Server Initial Setup (`server_setup.sh`)](#server-setup)
* [🐳 Docker Installer & Cleanup Manager (`manage_docker.sh`)](#docker-manager)
* [📊 System Diagnostic & Performance Monitor (`system_monitor.sh`)](#system-monitor-setup)
* [🐚 Fish Shell & Starship Theme Customizer (`setup_fish_starship.sh`)](#fish-setup)
* [☁️ Cloudflare Tunnel Setup (`setup_docker_cloudflare.sh`)](#cloudflare-tunnel)
* [💰 Actual Budget Personal Finance App (`setup_docker_actualbudget.sh`)](#actualbudget-setup)
* [🔥 Flame Dashboard Startpage (`setup_docker_flame.sh`)](#flame-setup)
* [📂 FileBrowser Web File Manager (`setup_docker_filebrowser.sh`)](#filebrowser)
* [📓 SiYuan Note-taking Workspace (`setup_docker_siyyuan.sh`)](#siyuan-note)
* [📇 Personal Digital Business Card (`setup_docker_website_buisnessCard.sh`)](#portfolio-bizcard)
* [🔍 Dozzle Real-Time Log Viewer (`setup_docker_dozzle.sh`)](#dozzle-setup)
* [🗄️ Postgres Database & Web API Suite (`setup_docker_postgres_postgrest.sh`)](#postgres-postgrest-setup)
* [🔗 Shlink URL Shortener (`setup_docker_shlink.sh`)](#shlink-setup)
* [🐳 Ubuntu Sandbox Playground (`setup_docker_ubuntu.sh`)](#ubuntu-setup)
* [🤖 Antigravity AI Workspace Setup (`setup_antigravity_project.sh`)](#antigravity-setup)

---

<a id="server-config"></a>
## 🚀 All-in-One VPS & Laptop Server Config (`configure_new_server.sh`)

### What it does
An all-in-one menu-driven utility designed for a brand-new VPS or a repurposed old home laptop. It updates packages, secures SSH connections, configures firewalls, creates swap space, installs Docker, and styles the terminal.

### Copy-Paste Run
```bash
sudo bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/configure_new_server.sh)"
```

### Options inside:
1. **System & Security**: Update packages, create a new admin account, change default SSH port to block hackers, install brute-force protection (Fail2Ban), configure firewall (UFW), and **disable laptop lid suspend** (so your old laptop server stays online when closed!).
2. **Network & Time**: Assign static local IPs, configure DNS servers, and sync system clocks.
3. **Memory & Disk**: Create memory swap space to run more apps on cheap servers.
4. **Docker Setup**: Automatic Docker installation, logs diagnostic checks, and space optimization.

---

<a id="server-setup"></a>
## 🖥️ Ubuntu Server Initial Setup (`server_setup.sh`)

### What it does
A modular post-installation wizard to configure and secure a fresh Ubuntu server. It prints system statistics (RAM, CPU, storage partition details) before showing you setup modules.

### Copy-Paste Run
```bash
sudo bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/server_setup.sh)"
```

---

<a id="docker-manager"></a>
## 🐳 Docker Installer & Cleanup Manager (`manage_docker.sh`)

### What it does
Installs Docker and Docker Compose correctly. It also cleans up server space by removing unused, orphaned container cache, dangling images, and local volumes.

### Copy-Paste Run
```bash
sudo bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/manage_docker.sh)"
```

---

<a id="system-monitor-setup"></a>
## 📊 System Diagnostic & Performance Monitor (`system_monitor.sh`)

### What it does
Prints current system statistics (kernel, RAM usage, storage breakdown, public IP address) and checks for/installs `btop` (a stunning real-time CLI monitor showing active CPU speeds, active network speeds, and running server processes).

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/system_monitor.sh)"
```

---

<a id="fish-setup"></a>
## 🐚 Fish Shell & Starship Theme Customizer (`setup_fish_starship.sh`)

### What it does
Replaces your boring black-and-white command terminal with a beautiful theme containing custom prompt icons, auto-suggestions, command highlighting, file type markers, and a welcome banner showing live server telemetry.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_fish_starship.sh)"
```

---

<a id="cloudflare-tunnel"></a>
## ☁️ Cloudflare Tunnel Setup (`setup_docker_cloudflare.sh`)

### What it does
Deploys a secure Cloudflare Zero Trust client. It allows you to access your server apps using public domains (like `files.yourname.com`) securely without doing risky router settings.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_cloudflare.sh)"
```

---

<a id="actualbudget-setup"></a>
## 💰 Actual Budget Personal Finance App (`setup_docker_actualbudget.sh`)

### What it does
Installs **Actual Budget**, a local-first personal finance tracker. It runs inside your browser, secures your financial details locally, and syncs encrypted bank templates with your devices.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_actualbudget.sh)"
```
* **Default Port**: `5006` (access at `http://your-server-ip:5006`).

---

<a id="flame-setup"></a>
## 🔥 Flame Dashboard Startpage (`setup_docker_flame.sh`)

### What it does
Installs a lightweight, elegant portal to organize all your self-hosted apps and search engines. It mounts the Docker socket so that running containers automatically populate on your homepage.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_flame.sh)"
```
* **Default Port**: `5005`.

---

<a id="filebrowser"></a>
## 📂 FileBrowser Web File Manager (`setup_docker_filebrowser.sh`)

### What it does
An online file manager similar to Google Drive or Dropbox. It lets you upload, download, edit, and organize files stored on your server directly from a web browser.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_filebrowser.sh)"
```
* **Default Port**: `8081`.

---

<a id="siyuan-note"></a>
## 📓 SiYuan Note-taking Workspace (`setup_docker_siyyuan.sh`)

### What it does
Installs **SiYuan**, a local-first, markdown-based personal database similar to Notion or Obsidian. The script ensures correct user permissions (PUID/PGID) so that your documents never lock up.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_siyyuan.sh)"
```
* **Default Port**: `6806`.

---

<a id="portfolio-bizcard"></a>
## 📇 Personal Digital Business Card (`setup_docker_website_buisnessCard.sh`)

### What it does
Creates a dedicated web server to host a personal business card, portfolio, or profile link page. You can customize files or drop in templates like **EnBizCard** directly into the project directory to publish it.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_website_buisnessCard.sh)"
```
* **Default Ports**: `8082` (business card), `8083` (portfolio).

---

<a id="dozzle-setup"></a>
## 🔍 Dozzle Real-Time Log Viewer (`setup_docker_dozzle.sh`)

### What it does
Spawns a real-time web console displaying log history for all running containers. Essential for troubleshooting database errors or server restarts.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_dozzle.sh)"
```
* **Default Port**: `8888`.

---

<a id="postgres-postgrest-setup"></a>
## 🗄️ Postgres Database & Web API Suite (`setup_docker_postgres_postgrest.sh`)

### What it does
Deploys a robust PostgreSQL 16 database running beside PostgREST (which auto-exposes database tables as clean REST APIs) and Adminer (a database visual editor). 

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_postgres_postgrest.sh)"
```

---

<a id="shlink-setup"></a>
## 🔗 Shlink URL Shortener (`setup_docker_shlink.sh`)

### What it does
Deploys a URL shortener utility complete with a visual dashboard. You can shorten links using your own custom domain (e.g. `s.example.com`) and monitor clicks.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_shlink.sh)"
```

---

<a id="ubuntu-setup"></a>
## 🐳 Ubuntu Sandbox Playground (`setup_docker_ubuntu.sh`)

### What it does
Deploys an isolated Ubuntu server container inside your server. Perfect as a "playground" to test raw commands, scripts, or package installs without risking your primary server system.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_docker_ubuntu.sh)"
```
* **Default SSH Port**: `2222`.

---

<a id="antigravity-setup"></a>
## 🤖 Antigravity AI Workspace Setup (`setup_antigravity_project.sh`)

### What it does
Initializes a workspace structure to allow coding assistants (like Google Antigravity) to help you develop, edit, or manage code and scripts safely inside your server.

### Copy-Paste Run
```bash
bash -c "$(curl -sSL https://ghannamsacademy.com/scripts/setup_antigravity_project.sh)"
```

---

## 🧭 Managing Your Apps After Setup

Once you run any of the setup scripts, they will generate folders (like `./actualbudget-deployment` or `./cloudflareContainer`) containing all of your configuration files.

To manage your apps, navigate inside that folder using `cd <folder_name>` and use these simple command shortcuts:

### 📋 View Application Logs (Troubleshooting)
```bash
docker compose logs -f
```
### 🛑 Stop the Application
```bash
docker compose down
```
### ▶️ Start the Application Again
```bash
docker compose up -d
```

---

## 🙋 FAQs & Common Troubleshooting

### "Permission Denied" when running setups
* **Why**: The script is trying to make system-level changes (like changing firewall rules or installing utilities) but doesn't have administrative access.
* **Fix**: Rerun the command prefixing it with `sudo` (e.g. `sudo ./server_setup.sh`).

### "Port already in use" error
* **Why**: Another application is already using that specific apartment number (port) on your server.
* **Fix**: The script will show a warning if the port is busy. Simply enter a different number (like `5007` instead of `5006`) when prompted.

### "Lid close turns off my server" (Laptop Servers)
* **Why**: By default, laptop operating systems go to sleep to save battery when the lid is closed.
* **Fix**: Run `configure_new_server.sh` and select option `16` (Disable Laptop Suspend). You can then close the lid, and it will remain active!

---

> [!NOTE]
> All scripts in this repository adhere to the **Ghannams Academy Code Quality & Safety Rules** (using `set -euo pipefail` safety traps, dynamic progress spinners, non-root user permissions, and standalone compose directory isolation).
