# 🛠️ Easy Docker Setup Scripts by Adib Builds

Welcome! This repository is a collection of simple, friendly scripts designed to help you host your own websites and applications using Docker—**even if you are not a tech expert!** 

Think of these scripts as automated assistants that do the heavy lifting of writing code and configuring server settings for you.

---

## 🚀 What Scripts Are in This Repository?

### 1. 📇 Portfolio & Business Card Installer (`createPortfolioBizcard.sh`)
This script sets up folders and files to host your personal websites, portfolios, or digital business cards.

* **What it does:** It creates a dedicated folder for your site, generates a clean template web page, and sets up Nginx (a tool that shows your website to visitors) to serve your site.
* **Why use it:** Instead of manually writing complicated server configurations, the script asks you a few simple questions (like your project name) and sets everything up perfectly.
* **Support Options:**
  1. **Business Card Only:** Setup a single site.
  2. **Website Only:** Setup a single site.
  3. **Business Card + Website:** Setup both sites at the same time on different ports.

### 2. 📓 SiYuan Private Note-Taking App (`siyyuan_install_docker.sh`)
SiYuan is a beautiful, secure, and private note-taking application (similar to Notion, but self-hosted and fully private).

* **What it does:** It downloads the SiYuan application, configures security passwords, sets up the workspace directory, and launches the app.
* **Why use it:** It automatically generates a secure access password for you, makes sure your data is saved safely in a dedicated folder, and opens it on the web port of your choice.

---

## 📋 Getting Started (Step-by-Step for Everyone)

### 1. Prerequisites (What you need first)
You need a Linux server with **Docker** installed. If you don't have it, don't worry! Run this command on your server to install Docker:
```bash
sudo apt-get update && sudo apt-get install -y docker.io
```

### 2. Downloading the Scripts
To get these scripts onto your server, copy and paste this command:
```bash
git clone https://github.com/Bme-Adib/Bash-Scripts.git
cd Bash-Scripts
```

---

## 💻 How to Use the Scripts

### How to use: Portfolio & Business Card Setup
1. Make the script ready to run:
   ```bash
   chmod +x createPortfolioBizcard.sh
   ```
2. Run the script:
   ```bash
   ./createPortfolioBizcard.sh
   ```
3. **Answer the simple prompts:**
   * **Project name:** Enter a name (e.g., `myprofile`).
   * **Selection:** Choose if you want a business card, website, or both.
   * **Port:** Choose an "apartment number" for your website (like `8080`).
   * **Review & Start:** The script will ask if you want to review the generated configuration and if you want to start it. Type **y** (yes) to launch it!
4. **Add your files:** Go to the folder created (e.g., `myprofile/biz/`) and replace the placeholder `index.html` file with your own website files!

---

### How to use: SiYuan Note App
1. Make the script ready to run:
   ```bash
   chmod +x siyyuan_install_docker.sh
   ```
2. Run the script:
   ```bash
   ./siyyuan_install_docker.sh
   ```
3. **Answer the simple prompts:**
   * Press **Enter** to accept the default folder, ports, and timezones, or type in your custom ones.
   * Note down the generated **Access Authorization Code** (this is your password to log in!).
   * Agree to start the container.
4. **Access your notes:** Open your browser and go to `http://<your-server-ip>:6806` (replace `6806` if you chose a different port).

---

## 💡 Quick Tips for Managing Your Apps
Docker runs your apps in the background. To control them, navigate to the app's folder (e.g., `cd myprofile` or `cd siyuan-workspace`) and run:

* **To Stop the app:**
  ```bash
  docker compose down
  ```
* **To Start/Restart the app:**
  ```bash
  docker compose up -d
  ```

---

## 👤 Author
**Adib Builds**  
Digital Infrastructure & Automation Specialist  
🔗 GitHub: [@Bme-Adib](https://github.com/Bme-Adib)
