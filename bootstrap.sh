#!/usr/bin/env bash
# ==============================================================================
# Raspberry Pi Hands-Off Bootstrap Script
# Installs Docker, sets up /opt/pi-stack, registers GitHub Runner, starts stack
# ==============================================================================
set -euo pipefail

# --- Configuration (Can be passed as env vars or prompted) ---
INSTALL_DIR="/opt/pi-stack"
CURRENT_USER="${SUDO_USER:-$USER}"

echo "======================================================"
echo " Starting Raspberry Pi Homelab Bootstrap"
echo " Target user: ${CURRENT_USER}"
echo " Install path: ${INSTALL_DIR}"
echo "======================================================"

# 1. Resolve pending locks and update OS
echo "==> Resolving any pending package locks or interrupted states..."
sudo dpkg --configure -a || true
sudo apt-get install -f -y || true

echo "==> Updating package indices and installing prerequisites..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release git jq

# 2. Install Docker using official script
if ! command -v docker &> /dev/null; then
    echo "==> Installing Docker Engine..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
else
    echo "==> Docker is already installed."
fi

# Ensure docker group exists and grant access to ALL human users (no sudo required)
echo "==> Configuring Docker permissions for all users..."
sudo groupadd -f docker

# Add all existing human users (UID >= 1000)
for u in $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd); do
    sudo usermod -aG docker "$u"
done
sudo usermod -aG docker "${CURRENT_USER}"

# Ensure any future users created with adduser are automatically in the docker group
if [ -f /etc/adduser.conf ]; then
    sudo sed -i 's/^#*ADD_EXTRA_GROUPS=.*/ADD_EXTRA_GROUPS=1/' /etc/adduser.conf
    if grep -q "^EXTRA_GROUPS=" /etc/adduser.conf; then
        sudo sed -i 's/^EXTRA_GROUPS=.*/EXTRA_GROUPS="docker"/' /etc/adduser.conf
    else
        echo 'EXTRA_GROUPS="docker"' | sudo tee -a /etc/adduser.conf > /dev/null
    fi
fi

# 3. Create shared docker network
sudo docker network create internal 2>/dev/null || true

# 4. Clone or pull the Git stack repo
echo "==> Setting up repository at ${INSTALL_DIR}..."
if [ -z "${REPO_URL:-}" ]; then
    read -rp "Enter your Git repository URL (e.g., https://github.com/user/pi-stack.git): " REPO_URL
fi

sudo mkdir -p "${INSTALL_DIR}"
sudo chown -R "${CURRENT_USER}:${CURRENT_USER}" "${INSTALL_DIR}"

if [ ! -d "${INSTALL_DIR}/.git" ]; then
    git clone "${REPO_URL}" "${INSTALL_DIR}"
else
    git -C "${INSTALL_DIR}" pull origin main
fi

# 5. Create common data directories
mkdir -p "${INSTALL_DIR}/data/homeassistant"
mkdir -p "${INSTALL_DIR}/data/mosquitto/config"
mkdir -p "${INSTALL_DIR}/data/mosquitto/data"

if [ ! -f "${INSTALL_DIR}/data/mosquitto/config/mosquitto.conf" ]; then
    cat << 'EOF' > "${INSTALL_DIR}/data/mosquitto/config/mosquitto.conf"
listener 1883
allow_anonymous true
EOF
fi

# 6. Setup GitHub Actions Self-Hosted Runner (Optional/Prompted)
RUNNER_DIR="/opt/actions-runner"
if [ ! -d "${RUNNER_DIR}" ]; then
    echo ""
    echo "------------------------------------------------------"
    echo " GitHub Actions Self-Hosted Runner Setup"
    echo " Get token from: Repo Settings -> Actions -> Runners -> New runner"
    echo " (Leave blank to skip CI/CD setup for now)"
    echo "------------------------------------------------------"
    
    if [ -z "${GH_TOKEN:-}" ]; then
        read -rp "GitHub Runner Registration Token (or press Enter to skip): " GH_TOKEN
    fi

    if [ -n "${GH_TOKEN}" ]; then
        # Detect Architecture (ARM64 vs x86_64)
        ARCH=$(uname -m)
        case "${ARCH}" in
            aarch64|arm64) RUNNER_ARCH="arm64" ;;
            x86_64)        RUNNER_ARCH="x64" ;;
            *)             echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
        esac

        echo "==> Fetching latest GitHub Actions Runner for ${RUNNER_ARCH}..."
        LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/v//')
        
        sudo mkdir -p "${RUNNER_DIR}"
        sudo chown -R "${CURRENT_USER}:${CURRENT_USER}" "${RUNNER_DIR}"
        cd "${RUNNER_DIR}"

        curl -o actions-runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${LATEST_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${LATEST_VERSION}.tar.gz"
        tar xzf ./actions-runner.tar.gz
        rm ./actions-runner.tar.gz

        echo "==> Configuring runner with GitHub..."
        # Extract owner/repo from URL
        REPO_NAME=$(echo "${REPO_URL}" | sed -E 's/.*github\.com[:\/](.*)\.git/\1/')
        if ./config.sh --url "https://github.com/${REPO_NAME}" --token "${GH_TOKEN}" --unattended --replace; then
            echo "==> Installing runner systemd service..."
            sudo ./svc.sh install "${CURRENT_USER}"
            sudo ./svc.sh start
            echo "==> GitHub Actions Runner installed and running!"
        else
            echo "==> [WARNING] GitHub runner registration failed (token may be expired or invalid)."
            echo "    Your Docker stack will still start! You can register the runner anytime later."
        fi
    fi
else
    echo "==> GitHub runner already configured."
fi

# 7. Start Docker Compose Stack
echo "==> Launching Docker Compose stack..."
cd "${INSTALL_DIR}"
sudo -u "${CURRENT_USER}" docker compose pull
sudo -u "${CURRENT_USER}" docker compose up -d --remove-orphans

# 8. Finished summary
IP_ADDR=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================================"
echo " Setup complete!"
echo " Home Assistant: http://${IP_ADDR}:8123"
echo " Project Directory: ${INSTALL_DIR}"
echo "======================================================"
echo "Note: If running as non-root, log out and back in for docker group changes to take effect."
