# 🛠️ Server Management & Automation Scripts

A collection of professional Bash scripts designed to streamline the deployment and management of self-hosted services, digital infrastructure, and web portfolios.

## 🚀 Scripts Included

### 1. Docker Business Card & Portfolio Manager (`manage_docker.sh`)
This script automates the deployment of static Nginx containers for digital business cards and personal portfolios. It handles directory creation, port mapping, and `docker-compose.yml` updates without overwriting existing services.

**Key Features:**
* **Dual Mode:** Choose between deploying a "Business Card Only" or a "Business Card + Website" stack.
* **Non-Destructive:** Uses `sed` to inject new services into your existing `docker-compose.yml` while maintaining proper indentation and spacing.
* **Automated Directory Setup:** Creates `${name}Biz` and `${name}Website` folders automatically.
* **Smart Networking:** Detects and adds external networks (like Cloudflare tunnels) only if they aren't already defined.

---

## 📋 How to Use

### Prerequisites
* A Linux environment (Ubuntu/Debian recommended).
* **Docker** and **Docker Compose** installed.
* A tool to generate your static site files. I highly recommend using [EnBizCard](https://enbizcard.vishnuraghav.com/) to create your professional digital business cards.

### Setup Instructions

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/your-username/your-repo-name.git](https://github.com/your-username/your-repo-name.git)
    cd your-repo-name
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x manage_docker.sh
    ```

3.  **Run the script:**
    ```bash
    ./manage_docker.sh
    ```

4.  **Follow the prompts:**
    * Enter the project name (e.g., `adib`).
    * Select the project type.
    * Assign unique ports.
    * Specify your Docker network (e.g., `proxy-net` or `cloudflare`).

5.  **Deploy:**
    The script will create the folders. Place your `index.html` and assets inside the newly created directories, then run:
    ```bash
    docker compose up -d
    ```

---

## 🎨 Recommended Workflow
1.  **Generate:** Create a stunning, responsive business card using [enbizcard.vishnuraghav.com](https://enbizcard.vishnuraghav.com/).
2.  **Automate:** Run `manage_docker.sh` to prepare your server environment.
3.  **Upload:** Move your generated files into the `${name}Biz` folder.
4.  **Connect:** Point your Cloudflare Tunnel or Reverse Proxy to the container name and port.

---

## 👤 Author
**Adib (Abdulmutalib)** Digital Infrastructure & Open Source Enthusiast.
