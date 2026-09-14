#!/bin/bash
set -ex

# Sweep across different identity cardinalities at 500 QPS:
# 5000 pods/RS -> 7 identities (Baseline O(1))
# 50 pods/RS   -> 700 identities (1 per node)
# 10 pods/RS   -> 3,500 identities (Multi-tenant)
# 1 pod/RS     -> 35,000 identities (Extreme 1:1 per-pod identity)
IDENTITY_SWEEPS=(5000 50 10 1)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/.." && pwd)"

for ppr in "${IDENTITY_SWEEPS[@]}"; do
    num_identities=$((35000 / ppr))
    MASTER_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')

    echo "========================================="
    echo "Cleaning up sandboxes-1 and resetting identity state..."
    echo "========================================="
    kubectl delete namespace sandboxes-1 --ignore-not-found=true
    kubectl wait --for=delete namespace/sandboxes-1 --timeout=5m || true
    
    # Fast identity purge so each tier starts with a pristine slate
    kubectl delete crd ciliumidentities.cilium.io || true
    sleep 3
    kubectl apply -f "${REPO_ROOT}/manifests/crds/ciliumidentities.yaml" || true
    sleep 2

    echo "==================================================================="
    echo "Running Benchmark with $ppr Pods/ReplicaSet (~$num_identities Identities) at 500 QPS"
    echo "==================================================================="
    
    export CL2_QPS=500
    export CL2_WORKLOAD_TYPE="replicaset"
    export CL2_PODS_PER_REPLICASET=$ppr
    export CL2_BURST=$ppr
    export REPORT_TAG="QPS500_${num_identities}identities_${ppr}ppr_microseg"
    export RESTART_CILIUM=false
    
    "${DIR}/run-test.sh"
    
    echo "Finished benchmark for $num_identities identities ($ppr pods/RS)"
done
