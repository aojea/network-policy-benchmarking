#!/bin/bash
# ==============================================================================
#  validate_run_pod_sandbox.sh
#  Standalone diagnostic script to validate CRI run_pod_sandbox latencies
#  and pod worker queues directly from Prometheus.
# ==============================================================================

KUBECONFIG_FILE="${KUBECONFIG:-${HOME}/.kube/config}"
WINDOW="${1:-5m}"

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "Warning: Kubeconfig not found. Falling back to default kubectl context..."
    KUBECMD="kubectl --request-timeout=5s"
else
    KUBECMD="kubectl --kubeconfig=$KUBECONFIG_FILE --request-timeout=5s"
fi

echo "========================================================================="
echo "   VALIDATING CRI run_pod_sandbox LATENCIES & POD WORKER SYNC (Last $WINDOW)"
echo "========================================================================="

# 0. Check Cluster API Server Reachability
echo "Checking connection to cluster API server..."
if ! $KUBECMD get --raw=/healthz >/dev/null 2>&1; then
    echo ""
    echo "❌ ERROR: Cannot reach Kubernetes API server."
    echo "Reason: The benchmark sweep completed its QPS test run and the cluster was torn down by 'teardown-cluster.sh'."
    echo ""
    echo "To test on an active cluster:"
    echo "  1. Re-create the cluster: ./create-netpol.sh"
    echo "  2. Or run this script while a benchmark sweep is actively running."
    exit 1
fi

echo "✓ Cluster API server is reachable."

# Helper function to execute PromQL queries via Prometheus pod in namespace 'monitoring'
query_prom() {
    local QUERY="$1"
    local ENCODED_QUERY=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")
    $KUBECMD exec -n monitoring prometheus-k8s-0 -c prometheus -- \
        curl -s "http://localhost:9090/api/v1/query?query=${ENCODED_QUERY}" 2>/dev/null
}

# 1. Cluster-wide run_pod_sandbox P50, P90, P99
echo ""
echo "--- 1. Cluster-wide CRI run_pod_sandbox Latencies (Window: $WINDOW) ---"
for QUANTILE in "0.50" "0.90" "0.99"; do
    PROM_QUERY="histogram_quantile(${QUANTILE}, sum(rate(kubelet_runtime_operations_duration_seconds_bucket{operation_type=\"run_pod_sandbox\"}[${WINDOW}])) by (le))"
    RESULT=$(query_prom "$PROM_QUERY" | python3 -c "import sys, json; data=json.load(sys.stdin); res=data.get('data',{}).get('result',[]); print(res[0]['value'][1] if res and res[0]['value'][1]!='NaN' else 'N/A')")
    printf "  run_pod_sandbox P%-2s: %s seconds\n" "${QUANTILE#0.}" "$RESULT"
done

# 2. Per-Node P99 run_pod_sandbox Breakdown
echo ""
echo "--- 2. Per-Node P99 run_pod_sandbox Latency Breakdown ---"
PROM_QUERY="histogram_quantile(0.99, sum(rate(kubelet_runtime_operations_duration_seconds_bucket{operation_type=\"run_pod_sandbox\"}[${WINDOW}])) by (le, instance))"
query_prom "$PROM_QUERY" | python3 -c '
import sys, json
data = json.load(sys.stdin)
results = data.get("data", {}).get("result", [])
if not results:
    print("  No metrics returned for per-node breakdown.")
for item in results:
    instance = item["metric"].get("instance", "unknown")
    val = item["value"][1]
    if val != "NaN":
        print(f"  Node Instance: {instance:<25} | P99 run_pod_sandbox: {float(val):.3f}s")
'

# 3. Kubelet Pod Worker Sync & Queue Duration
echo ""
echo "--- 3. Kubelet Pod Workers Queue Duration (P99) ---"
PROM_QUERY="histogram_quantile(0.99, sum(rate(kubelet_pod_worker_duration_seconds_bucket[${WINDOW}])) by (le))"
POD_WORKERS_P99=$(query_prom "$PROM_QUERY" | python3 -c "import sys, json; data=json.load(sys.stdin); res=data.get('data',{}).get('result',[]); print(res[0]['value'][1] if res and res[0]['value'][1]!='NaN' else 'N/A')")
echo "  pod_workers P99 Sync Duration: ${POD_WORKERS_P99} seconds"

# 4. Comparison across CRI Operations
echo ""
echo "--- 4. Comparison across CRI Operations (P99 Latency) ---"
PROM_QUERY="histogram_quantile(0.99, sum(rate(kubelet_runtime_operations_duration_seconds_bucket[${WINDOW}])) by (le, operation_type))"
query_prom "$PROM_QUERY" | python3 -c '
import sys, json
data = json.load(sys.stdin)
results = data.get("data", {}).get("result", [])
for item in results:
    op = item["metric"].get("operation_type", "unknown")
    val = item["value"][1]
    if val != "NaN":
        print(f"  CRI Operation: {op:<20} | P99 Latency: {float(val):.4f}s")
'

echo "========================================================================="
