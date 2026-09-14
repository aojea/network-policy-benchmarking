#!/bin/bash
set -ex
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

echo "========================================="
echo "Step 1: Tearing down existing Netpol cluster..."
echo "========================================="
CLUSTER_NAME=agentic-cilium.k8s.local ./teardown-cluster.sh || true

echo "========================================="
echo "Step 2: Creating new Cilium cluster..."
echo "========================================="
./create-cilium.sh

echo "========================================="
echo "Step 3: Running Cilium Identity Cardinality Sweep..."
echo "========================================="
./run-identity-sweep.sh

echo "========================================="
echo "Full Cilium Identity Cardinality Benchmark Sweep complete!"
echo "========================================="
