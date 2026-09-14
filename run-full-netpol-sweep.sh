#!/bin/bash
set -ex
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

echo "========================================="
echo "Step 1: Tearing down existing Cilium cluster..."
echo "========================================="
CLUSTER_NAME=agentic-cilium.k8s.local ./teardown-cluster.sh || true

echo "========================================="
echo "Step 2: Creating new Kindnet / NetPol cluster..."
echo "========================================="
./create-netpol.sh

echo "========================================="
echo "Step 3: Running QPS sweep (50, 100, 200, 500) for Kindnet..."
echo "========================================="
./run-qps-sweep.sh

echo "========================================="
echo "Full Kindnet benchmark sweep complete!"
echo "========================================="
