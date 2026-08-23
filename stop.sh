#!/usr/bin/env bash
set -euo pipefail

# Stoppt und löscht den lokalen Korifi-kind-Cluster.
CLUSTER_NAME="${CLUSTER_NAME:-korifi}"

echo "=== Korifi on Kind: Stop ==="
kind delete cluster --name "$CLUSTER_NAME"
echo "Cluster '$CLUSTER_NAME' gelöscht."
