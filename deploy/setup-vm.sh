#!/bin/bash
set -e

# 1. Update and install basic tools
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release unattended-upgrades

# 2. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 3. Create Swap File (4GB for safety)
if [ ! -f /swapfile ]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# 4. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# 5. Configure Firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
# Allow SSH over Tailscale (Tailscale IP)
sudo ufw allow in on tailscale0 to any port 22
echo "y" | sudo ufw enable

# 6. Enable Unattended Upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# 7. Setup Daily Docker Cleanup (Cron)
# This prevents the disk from filling up with old GitHub Runner image layers
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/docker system prune -af --volumes --filter \"until=24h\"") | crontab -

echo "Setup complete. Please run 'sudo tailscale up' to authenticate."
echo "Daily maintenance cron added (3 AM)."

