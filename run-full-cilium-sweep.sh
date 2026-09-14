#!/bin/bash
set -ex
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

echo "========================================="
echo "Step 1: Tearing down existing netpol cluster..."
echo "========================================="
CLUSTER_NAME=agentic-netpol.k8s.local ./teardown-cluster.sh || true

echo "========================================="
echo "Step 2: Creating new Cilium cluster..."
echo "========================================="
./create-cilium.sh

echo "========================================="
echo "Step 3: Running QPS sweep (50, 100, 200, 500)..."
echo "========================================="
./run-qps-sweep.sh

echo "========================================="
echo "Full overnight Cilium benchmark sweep complete!"
echo "========================================="
