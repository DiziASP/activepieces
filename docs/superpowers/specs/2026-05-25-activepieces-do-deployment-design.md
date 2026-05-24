# Design Spec: Simple & Hardened DigitalOcean Deployment for Activepieces

## 1. Overview
The goal is to deploy Activepieces on a DigitalOcean VM with a "Big Red Button" (manual) deployment flow, ensuring the VM is hardened and only accessible via Tailscale. This approach avoids infrastructure bloat by using a minimal set of scripts and standard GitHub Actions patterns.

## 2. Architecture & Security

### 2.1 Infrastructure
- **Provider:** DigitalOcean Droplet (Ubuntu).
- **Network:** Private overlay network via **Tailscale**.
- **Firewall (UFW):** `default deny incoming`. Only `tailscale0` interface is allowed. The VM is invisible to the public internet.
- **Access:** SSH and Activepieces Web UI are only accessible when connected to the Tailscale network.

### 2.2 Security Hardening
- **No Inbound Ports:** No public ports (80, 443, 22) are open to the internet.
- **Isolated Services:** Postgres and Redis run in Docker, bound only to the internal Docker network.
- **Least Privilege:** Deployment actions are handled by a dedicated GitHub Runner user with restricted Docker access.
- **OS Maintenance:** `unattended-upgrades` enabled for security patches.

## 3. Repository Management (The "Anti-Spaghetti" Plan)

To keep your deployment logic separate from the core Activepieces source code and enable clean future contributions:

### 3.1 Branch Strategy (Fork & Branch)
- **`main` Branch:** Always kept clean and synced with the official Activepieces repository (`upstream`). No deployment scripts or custom configurations are committed here.
- **`production` Branch:** Derived from `main`, this branch contains all deployment scripts (`setup-vm.sh`), CI/CD workflows (`deploy.yml`), and production Docker configurations.
- **Contribution Flow:** When developing a new feature or fix, create a branch from `main`. This ensures your PRs only contain core code changes.
- **Deployment Flow:** Periodically merge `main` into `production`. Your deployment logic remains isolated on the `production` branch.

## 4. Deployment Flow (The "Big Red Button")

### 4.1 Components
1. **GitHub Actions (Hosted):** Handles the resource-intensive build process (TypeScript compilation, Docker image creation).
2. **GitHub Container Registry (GHCR):** Stores versioned Docker images.
3. **Self-Hosted GitHub Runner:** Installed on the DigitalOcean VM. It polls GitHub for deployment instructions, removing the need for inbound SSH keys in CI.

### 4.2 The Workflow (`workflow_dispatch`)
1. **Input:** User provides a Git Tag (e.g., `v0.83.0`) or Branch.
2. **Build Phase:** GitHub-hosted runner builds the `app` and `worker` images, tags them, and pushes to GHCR.
3. **Deploy Phase:** The workflow targets the `self-hosted` runner on the VM.
   - The runner pulls the new images from GHCR.
   - Updates the `docker-compose.yml` environment.
   - Restarts services: `docker compose up -d --remove-orphans`.
   - Performs a health check against the local API.

## 5. Implementation Plan

### 5.1 Phase 1: VM Preparation
- Create a `setup-vm.sh` script to:
  - Install Docker & Docker Compose.
  - Install Tailscale and provide instructions for authentication.
  - Configure UFW to block all but Tailscale.
  - Setup the GitHub Self-Hosted Runner.

### 4.2 Phase 2: Production Configuration
- Create `deploy/docker-compose.prod.yml`:
  - Optimized for production (no dev volumes, resource limits).
  - Use environment variables for all sensitive config.

### 4.3 Phase 3: CI/CD Pipeline
- Create `.github/workflows/deploy.yml`:
  - `workflow_dispatch` configuration.
  - Docker build-and-push logic.
  - Deployment step targeting the `self-hosted` label.

## 6. Verification Plan
1. **Security Scan:** Verify that `nmap` from a public IP shows all ports filtered/closed.
2. **Connectivity:** Confirm Web UI is reachable only when Tailscale is connected.
3. **Deployment:** Manually trigger a deploy for a specific tag and verify the running version matches.
