#!/usr/bin/env bash
# Create a 3-node kind cluster without the default CNI, then install Cilium
# and enable Hubble.
# Sources:
#   https://kind.sigs.k8s.io/docs/user/quick-start/
#   https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
#   https://docs.cilium.io/en/stable/observability/hubble/setup/
# Run as a normal user in the docker group, after 01-03.
set -euo pipefail

CLUSTER_NAME=kind
CILIUM_VERSION=1.20.4

# Find kind-config.yaml next to this script, wherever it is run from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker info >/dev/null 2>&1; then
  echo "Cannot talk to Docker without sudo." >&2
  echo "Log out and log in again after 01-install-docker.sh, then retry." >&2
  exit 1
fi

# Skip each step that is already done, so the script can be run again.
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists, skipping kind create."
else
  kind create cluster --name "$CLUSTER_NAME" --config "$SCRIPT_DIR/kind-config.yaml"
fi

if kubectl -n kube-system get daemonset cilium >/dev/null 2>&1; then
  echo "Cilium is already installed, skipping cilium install."
else
  cilium install --version "$CILIUM_VERSION"
fi
cilium status --wait

if kubectl -n kube-system get deployment hubble-relay >/dev/null 2>&1; then
  echo "Hubble Relay already exists, skipping cilium hubble enable."
else
  cilium hubble enable
fi
cilium status --wait

echo
kubectl get nodes -o wide
echo
hubble status -P || echo "Hubble Relay is not ready yet. Try again later: hubble status -P"
