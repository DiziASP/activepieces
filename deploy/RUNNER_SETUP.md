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
