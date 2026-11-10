#!/usr/bin/env bash
# Install the command-line tools: kubectl, kind, cilium, and hubble.
# Sources:
#   https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
#   https://kind.sigs.k8s.io/docs/user/quick-start/
#   https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
#   https://docs.cilium.io/en/stable/observability/hubble/setup/
# Run as a normal user; sudo is used where needed.
set -euo pipefail

# Pinned versions, so a rebuild gets the same tools.
KUBECTL_VERSION=v1.37.2
KIND_VERSION=v0.33.0
CILIUM_CLI_VERSION=v0.20.2
HUBBLE_VERSION=v1.20.2

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Download into a temporary directory that is removed on exit, even on error.
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# kubectl: the Kubernetes command-line tool.
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# kind: runs Kubernetes clusters using Docker containers as nodes.
curl -fsSLo kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
sudo install -o root -g root -m 0755 kind /usr/local/bin/kind

# cilium: installs and checks Cilium in the cluster.
curl -fsSL --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "cilium-linux-${ARCH}.tar.gz.sha256sum"
sudo tar xzvfC "cilium-linux-${ARCH}.tar.gz" /usr/local/bin

# hubble: queries network flows from Hubble Relay.
curl -fsSL --remote-name-all "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "hubble-linux-${ARCH}.tar.gz.sha256sum"
sudo tar xzvfC "hubble-linux-${ARCH}.tar.gz" /usr/local/bin

echo
kubectl version --client
kind version
cilium version --client
hubble version
echo "Next: ./03-tune-sysctl.sh"
