# 🛠️ Bash Scripts

A professional collection of Bash scripts tailored for managing self-hosted infrastructure, Docker environments, and automated deployments.

## 🚀 Featured Scripts

### 1. Docker Portfolio & Business Card Manager (`createPortfolioBizcard.sh`)
This script simplifies the process of hosting multiple static websites on a single server. It is specifically designed to work with static site generators to deploy digital business cards and personal portfolios quickly.

**Key Features:**
* **Intelligent Injection:** Adds new services to your existing `docker-compose.yml` without overwriting previous configurations.
* **Automatic Directory Creation:** Generates the necessary host folders (`${name}Biz` and `${name}Website`) automatically to prevent Nginx 403 errors.
* **Flexible Deployment:** Supports two modes:
    1. **Business Card Only**: Deploys a single Nginx service.
    2. **Business Card + Website**: Deploys two linked Nginx services for a complete personal brand.
* **Network Integration:** Seamlessly attaches containers to existing external networks (e.g., `cloudflare` or `proxy-net`).
* **Clean Formatting:** Ensures the generated YAML is human-readable with proper spacing and indentation.

---

## 📋 Getting Started

### Prerequisites
* A Linux-based server (Ubuntu/Debian recommended).
* **Docker** and **Docker Compose** installed.
* Static web assets. For high-quality digital business cards, use [EnBizCard](https://enbizcard.vishnuraghav.com/).

### Installation & Usage

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/Bme-Adib/Bash-Scripts.git](https://github.com/Bme-Adib/Bash-Scripts.git)
   cd Bash-Scripts
   ```
2. **Grant execution permissions:**
   ```bash
   chmod +x createPortfolioBizcard.sh
   ```
3. **Execute the script:**
```bash
   ./createPortfolioBizcard.sh
```
4. **Follow the interactive prompts:**
   Provide a project name (this becomes your container and folder name).
    - Choose your deployment type.
    - Enter unique host ports.
    - Define your external network if applicable.
5. **Deploy the stack:**
Once the script finishes, move your HTML files into the newly created directories and run:
```bash
docker compose up -d
```
---

## 🎨 Recommended Workflow
1. **Design:** Generate your digital card at [enbizcard.vishnuraghav.com](https://enbizcard.vishnuraghav.com/).
2. **Setup:** Run `createPortfolioBizcard.sh` to prepare the server structure.
3. **Transfer:** Upload your assets to the `${name}Biz` directory.
4. **Proxy:** Configure your Cloudflare Tunnel or Reverse Proxy to point to the container name and assigned port.

---

## 👤 Author
**Adib**  
Digital Infrastructure & Automation Specialist
