# Raspberry Pi GitOps Homelab Stack

A modular, hands-off setup for running Home Assistant and companion services on a Raspberry Pi using Docker Compose and GitHub Actions.

## Quick Start

### 1. Initialize Git and Push to GitHub
```bash
cd /Users/nataizya/Documents/Playground/Pi
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<YOUR_USERNAME>/<YOUR_REPO>.git
git push -u origin main
```

### 2. Run Bootstrap on the Pi (1 Command)
SSH into your Raspberry Pi and execute:
```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR_USERNAME>/<YOUR_REPO>/main/bootstrap.sh | bash
```
Or pass the parameters non-interactively:
```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR_USERNAME>/<YOUR_REPO>/main/bootstrap.sh | \
  REPO_URL="https://github.com/<YOUR_USERNAME>/<YOUR_REPO>.git" \
  GH_TOKEN="<YOUR_RUNNER_REGISTRATION_TOKEN>" \
  bash
```

---

## Adding New Services (The Cookbook)

To add any service (e.g., `zigbee2mqtt` or `adguard`) with 0 keystrokes on the Pi:

1. Scaffold the service from template:
   ```bash
   make new name=zigbee2mqtt
   ```
2. Edit `services/zigbee2mqtt/compose.yaml` with the desired container image, ports, and mounts.
3. Commit and push:
   ```bash
   git commit -am "feat: add zigbee2mqtt"
   git push
   ```
4. The self-hosted runner automatically pulls changes and deploys the new service on the Pi.
