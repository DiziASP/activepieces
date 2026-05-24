#!/bin/bash
set -e

# 1. Update and install basic tools
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release unattended-upgrades

# 2. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 3. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# 4. Configure Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
# Allow SSH over Tailscale (Tailscale IP)
sudo ufw allow in on tailscale0 to any port 22
echo "y" | sudo ufw enable

# 5. Enable Unattended Upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

echo "Setup complete. Please run 'sudo tailscale up' to authenticate."
