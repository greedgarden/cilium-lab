#!/usr/bin/env bash
# Install Docker Engine from Docker's official apt repository (Ubuntu).
# Source: https://docs.docker.com/engine/install/ubuntu/
# Run as a normal user; sudo is used where needed.
set -euo pipefail

# Add Docker's official GPG key:
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

# Install Docker Engine, containerd, and the Buildx and Compose plugins.
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Let the current user run docker without sudo.
# Source: https://docs.docker.com/engine/install/linux-postinstall/
sudo usermod -aG docker "$USER"

echo
echo "Docker installed. Log out and log in again so the docker group takes effect,"
echo "then check with: docker run hello-world"
echo "Next: ./02-install-tools.sh"
