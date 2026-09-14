#!/bin/bash
set -ex

# =============================================================================
# Scenario C - Bidirectional Mesh Sweep
# =============================================================================
# Tests whether Cilium's per-endpoint eBPF policy model degrades under a flat
# peer-to-peer topology where Kindnet's node-global nftables sets are invariant.
#
# Unlike the hub & spoke sweep (run-identity-sweep.sh), here EVERY sandbox
# endpoint on EVERY node must expand all N sandbox identities, in both
# directions. See manifests/policy-scenarios/README.md.
#
# Tier plan (35,000 pods total, 720 worker nodes, ~50 pods/node):
#   5000 pods/RS ->     7 identities ->     14 entries/endpoint  (control)
#     50 pods/RS ->   700 identities ->  1,400 entries/endpoint
#     10 pods/RS -> 3,500 identities ->  7,000 entries/endpoint
#
# DELIBERATELY EXCLUDES 1 pod/RS (35,000 identities):
#   bidirectional mesh needs ~2N = 70,000 entries per endpoint, which exceeds
#   bpf-policy-map-max: 65536. That yields an uninformative map overflow
#   instead of a measurable latency curve.
# =============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESH_SWEEPS=(5000 50 10)

CILIUM_IDENTITY_CRD="${DIR}/manifests/crds/ciliumidentities.yaml"

# Guard: bidirectional mesh needs ~2N entries per endpoint. Refuse to run a
# tier that would overflow the configured per-endpoint policy map.
BPF_POLICY_MAP_MAX=$(kubectl get configmap cilium-config -n kube-system -o jsonpath='{.data.bpf-policy-map-max}')
BPF_POLICY_MAP_MAX="${BPF_POLICY_MAP_MAX:-16384}"
echo "Detected bpf-policy-map-max=${BPF_POLICY_MAP_MAX}"

# Preflight: clusterloader2 aborts the whole run if the Prometheus stack does
# not become healthy, and it does that ~15 min into setup for EVERY tier.
#
# The monitoring node runs the Prometheus TSDB on an emptyDir backed by its
# root disk (CL2_PROMETHEUS_PVC_ENABLED=false). Scraping 720 nodes and 35k pods
# fills a 64 GB disk within a day, after which prometheus-k8s-0 wedges in
# CreateContainerConfigError ("no space left on device") and every tier fails
# during setup having produced zero data.
#
# Fail fast here instead. Remediate by deleting the monitoring namespace, which
# frees the emptyDir; clusterloader2 recreates the stack on the next run.
# Select by the kOps instancegroup label, which kOps sets at boot. Do NOT use
# prometheus-pool=true here: run-test.sh applies that label later, so on a
# freshly recreated node this check would match nothing and pass vacuously.
PROM_NODES=$(kubectl get nodes -l kops.k8s.io/instancegroup=prometheus-nodes -o name)
if [ -z "${PROM_NODES}" ]; then
    echo "FATAL: no node with kops.k8s.io/instancegroup=prometheus-nodes found." >&2
    echo "       The Prometheus stack has nowhere to schedule and every tier will abort." >&2
    exit 1
fi
for node in ${PROM_NODES}; do
    if kubectl get "${node}" -o jsonpath='{.status.conditions[?(@.type=="DiskPressure")].status}' | grep -q True; then
        echo "FATAL: ${node} reports DiskPressure. The Prometheus stack will not come up" >&2
        echo "       and every tier will abort during clusterloader2 setup." >&2
        echo "       Remediate with: kubectl delete namespace monitoring" >&2
        echo "       If the disk stays full (orphaned emptyDir), recreate the node:" >&2
        echo "         gcloud compute instance-groups managed recreate-instances \\" >&2
        echo "           d-prometheus-nodes-agentic-cilium-k8s-local --zone us-east1-d \\" >&2
        echo "           --instances <node> --project ${PROJECT:-gke-maspinwall-dev-2}" >&2
        exit 1
    fi
    if ! kubectl get "${node}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True; then
        echo "FATAL: ${node} is not Ready." >&2
        exit 1
    fi
done
echo "Preflight OK: monitoring node present, Ready, no DiskPressure."

for ppr in "${MESH_SWEEPS[@]}"; do
    num_identities=$((35000 / ppr))
    entries_per_endpoint=$((num_identities * 2))

    if [ "$entries_per_endpoint" -ge "$BPF_POLICY_MAP_MAX" ]; then
        echo "SKIPPING ${num_identities} identities: needs ~${entries_per_endpoint} entries/endpoint," \
             "which exceeds bpf-policy-map-max=${BPF_POLICY_MAP_MAX}."
        continue
    fi

    echo "========================================="
    echo "Cleaning up sandboxes-1 and resetting identity state..."
    echo "========================================="
    kubectl delete namespace sandboxes-1 --ignore-not-found=true --wait=false

    # Drain fully before proceeding. Tearing down ~35,000 pods runs a CNI DEL
    # per pod and takes ~15 min at observed rates (~40 pods/sec).
    #
    # Do NOT shortcut this with --grace-period=0 --force: that removes pods from
    # etcd without running CNI DEL, orphaning Cilium endpoints and leaking IPs
    # on the nodes, which corrupts the very thing this benchmark measures.
    #
    # Hard-fail instead of proceeding: clusterloader2 cannot create objects in a
    # Terminating namespace, and a partial run silently produces garbage data.
    drain_deadline=$(( $(date +%s) + 1800 ))
    while kubectl get namespace sandboxes-1 >/dev/null 2>&1; do
        if [ "$(date +%s)" -gt "$drain_deadline" ]; then
            echo "FATAL: sandboxes-1 still present after 30m; refusing to start a tier" \
                 "in a Terminating namespace. Investigate before re-running." >&2
            exit 1
        fi
        remaining=$(kubectl get pods -n sandboxes-1 --no-headers 2>/dev/null | wc -l)
        echo "  [$(date -u +%H:%M:%S)] draining sandboxes-1, pods remaining: ${remaining}"
        sleep 30
    done
    echo "  sandboxes-1 fully drained."

    # Purge the identity space so each tier starts clean. The 65,280 identity
    # ceiling is CUMULATIVE across runs, so without this a multi-tier sweep
    # exhausts the allocator and strands pods for reasons unrelated to topology.
    kubectl delete crd ciliumidentities.cilium.io || true
    sleep 3
    kubectl apply -f "${CILIUM_IDENTITY_CRD}" || true
    sleep 2

    echo "==================================================================="
    echo "MESH sweep: ${ppr} Pods/ReplicaSet (~${num_identities} identities) at 500 QPS"
    echo "  ~${entries_per_endpoint} policy entries per endpoint"
    echo "  ~$((entries_per_endpoint * 50)) policy entries per node (50 pods/node)"
    echo "==================================================================="

    export CL2_QPS=500
    export CL2_WORKLOAD_TYPE="replicaset"
    export CL2_PODS_PER_REPLICASET=$ppr
    export CL2_BURST=$ppr
    export CL2_SANDBOX_PEER_MODE="mesh"
    export REPORT_TAG="QPS500_${num_identities}identities_${ppr}ppr_mesh"
    export RESTART_CILIUM=false

    ./run-test.sh

    echo "Finished MESH benchmark for ${num_identities} identities (${ppr} pods/RS)"
done

echo "Mesh sweep complete. Compare schedule_to_run against the hub & spoke"
echo "results in benchmark_results.md Section 4.B (flat 1.31s - 1.53s)."
