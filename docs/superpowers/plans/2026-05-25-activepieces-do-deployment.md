# DigitalOcean Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Activepieces on a hardened DigitalOcean VM accessible only via Tailscale with a manual GitHub Actions deployment flow.

**Architecture:** Use a GitHub-hosted runner to build Docker images and push them to GHCR. A self-hosted runner on the VM pulls the images and updates the containers. The VM is secured by Tailscale and UFW.

**Tech Stack:** Docker, Docker Compose, Tailscale, GitHub Actions, DigitalOcean, Ubuntu.

---

### Task 1: Repository Preparation (Fork & Branch)

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Create the production branch**

Run: `git checkout -b production`

- [ ] **Step 2: Verify current branch**

Run: `git branch --show-current`
Expected: `production`

- [ ] **Step 3: Ensure documentation is on this branch**

The design spec should already be present.
Run: `ls docs/superpowers/specs/2026-05-25-activepieces-do-deployment-design.md`
Expected: File exists.

- [ ] **Step 4: Commit branch state**

Run: `git commit --allow-empty -m "chore: initialize production branch for deployment"`

---

### Task 2: VM Setup Script

**Files:**
- Create: `deploy/setup-vm.sh`

- [ ] **Step 1: Write the setup script**

```bash
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
```

- [ ] **Step 2: Make script executable**

Run: `chmod +x deploy/setup-vm.sh`

- [ ] **Step 3: Commit**

Run: `git add deploy/setup-vm.sh && git commit -m "feat: add VM setup script"`

---

### Task 3: Production Docker Compose

**Files:**
- Create: `deploy/docker-compose.prod.yml`

- [ ] **Step 1: Write the production compose file**

```yaml
services:
  app:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/activepieces-app:${TAG}
    container_name: activepieces-app
    restart: unless-stopped
    ports:
      - '127.0.0.1:8080:80'
    depends_on:
      - postgres
      - redis
    env_file: .env
    environment:
      - AP_CONTAINER_TYPE=APP
    volumes:
      - ./cache:/usr/src/app/cache
    networks:
      - activepieces

  worker:
    image: ghcr.io/${GITHUB_REPOSITORY_OWNER}/activepieces-worker:${TAG}
    restart: unless-stopped
    depends_on:
      - app
    env_file: .env
    environment:
      - AP_CONTAINER_TYPE=WORKER
    deploy:
      replicas: 2
    volumes:
      - ./cache:/usr/src/app/cache
    networks:
      - activepieces

  postgres:
    image: 'pgvector/pgvector:pg16'
    container_name: postgres
    restart: unless-stopped
    env_file: .env
    environment:
      - 'POSTGRES_DB=${AP_POSTGRES_DATABASE}'
      - 'POSTGRES_PASSWORD=${AP_POSTGRES_PASSWORD}'
      - 'POSTGRES_USER=${AP_POSTGRES_USERNAME}'
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - activepieces

  redis:
    image: 'redis:7.2'
    container_name: redis
    restart: unless-stopped
    volumes:
      - 'redis_data:/data'
    networks:
      - activepieces

volumes:
  postgres_data:
  redis_data:

networks:
  activepieces:
```

- [ ] **Step 2: Commit**

Run: `git add deploy/docker-compose.prod.yml && git commit -m "feat: add production docker-compose"`

---

### Task 4: GitHub Actions Deployment Workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Step 1: Write the deployment workflow**

```yaml
name: Deploy to DigitalOcean

on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag to deploy'
        required: true
        default: 'latest'

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.inputs.tag }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push App
        uses: docker/build-push-action@v5
        with:
          context: .
          file: Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/activepieces-app:${{ github.event.inputs.tag }}
            ghcr.io/${{ github.repository_owner }}/activepieces-app:latest
          build-args: |
            AP_CONTAINER_TYPE=APP

      - name: Build and push Worker
        uses: docker/build-push-action@v5
        with:
          context: .
          file: Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/activepieces-worker:${{ github.event.inputs.tag }}
            ghcr.io/${{ github.repository_owner }}/activepieces-worker:latest
          build-args: |
            AP_CONTAINER_TYPE=WORKER

  deploy:
    needs: build-and-push
    runs-on: self-hosted
    steps:
      - name: Pull latest images
        run: |
          export TAG=${{ github.event.inputs.tag }}
          export GITHUB_REPOSITORY_OWNER=${{ github.repository_owner }}
          docker compose -f deploy/docker-compose.prod.yml pull

      - name: Deploy containers
        run: |
          export TAG=${{ github.event.inputs.tag }}
          export GITHUB_REPOSITORY_OWNER=${{ github.repository_owner }}
          docker compose -f deploy/docker-compose.prod.yml up -d --remove-orphans

      - name: Health check
        run: |
          sleep 30
          curl -f http://localhost:8080/api/v1/health || exit 1
```

- [ ] **Step 2: Commit**

Run: `git add .github/workflows/deploy.yml && git commit -m "feat: add deployment workflow"`

---

### Task 5: Self-Hosted Runner Documentation

**Files:**
- Create: `deploy/RUNNER_SETUP.md`

- [ ] **Step 1: Write instructions for the self-hosted runner**

```markdown
# Setting up Self-Hosted Runner on DigitalOcean

1. Go to your GitHub Repository -> Settings -> Actions -> Runners.
2. Click "New self-hosted runner".
3. Select "Linux" and architecture (likely x64).
4. Follow the commands on the VM to download and configure the runner.
5. When prompted for labels, add `self-hosted`.
6. Use the `svc.sh` script to install it as a service:
   ```bash
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```
```

- [ ] **Step 2: Commit**

Run: `git add deploy/RUNNER_SETUP.md && git commit -m "docs: add self-hosted runner setup instructions"`
