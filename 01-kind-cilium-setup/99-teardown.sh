#!/usr/bin/env bash
# Delete the kind cluster. Docker, the CLI tools, and the sysctl settings stay
# installed, so 04-create-cluster.sh can build a fresh cluster again.
set -euo pipefail

CLUSTER_NAME=kind

kind delete cluster --name "$CLUSTER_NAME"
docker ps --format '{{.Names}}'
