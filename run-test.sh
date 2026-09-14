#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL2_DIR="${CL2_DIR:-${DIR}/../perf-tests/clusterloader2}"
TEST_CONFIG_DIR="${DIR}/manifests/agentic-sandbox"

export PROJECT="${PROJECT:-gke-maspinwall-dev-2}"
export CLUSTER_NAME="${CLUSTER_NAME:-$(kubectl config current-context)}"
export CLUSTER_ZONE="${CLUSTER_ZONE:-us-east1-b}"

export CL2_QPS="${CL2_QPS:-100}"
REPORT_TAG="${REPORT_TAG:-QPS${CL2_QPS}}"
REPORT_DIR="${DIR}/artifacts_pods/${CLUSTER_NAME}_${REPORT_TAG}_$(date +"%Y-%m-%d_%H-%M-%S")"

export ARTIFACTS="${REPORT_DIR}"
export RUN_ORIGINAL_SCRIPTS=false
if [[ "$CLUSTER_NAME" == *"cilium"* ]]; then
  export CL2_ENABLE_CILIUM_CNI_LOGS=false
  export CL2_CNI_TYPE="cilium"
elif [[ "$CLUSTER_NAME" == *"calico"* ]]; then
  export CL2_ENABLE_CILIUM_CNI_LOGS=false
  export CL2_CNI_TYPE="calico"
elif [[ "$CLUSTER_NAME" == *"netpol"* ]]; then
  export CL2_ENABLE_CILIUM_CNI_LOGS=false
  export CL2_CNI_TYPE="netpol"
elif [[ "$CLUSTER_NAME" == *"flannel"* ]]; then
  export CL2_ENABLE_CILIUM_CNI_LOGS=false
  export CL2_CNI_TYPE="flannel"
else
  export CL2_ENABLE_CILIUM_CNI_LOGS=false
  export CL2_CNI_TYPE="none"
fi
export CL2_USE_HT_SCHEDULER=false
export GODEBUG=http2client=0
export CL2_PROMETHEUS_MEMORY_LIMIT_FACTOR=64
export CL2_PROMETHEUS_KUBELET_MEMORY_SCALE_FACTOR=64
export CL2_PROMETHEUS_SCRAPE_CILIUM_AGENT_PORT=prometheus
export CL2_PROMETHEUS_SCRAPE_CILIUM_AGENT=true
export CL2_PROMETHEUS_SCRAPE_NETPOL=true
export CL2_PROMETHEUS_SCRAPE_NODE_EXPORTER=true
export CL2_PROMETHEUS_TOLERATE_MASTER=false
export CL2_PROMETHEUS_PVC_ENABLED=false
export CL2_PROMETHEUS_NODE_SELECTOR="prometheus-pool: \"true\""
export CL2_CACHE_IMAGE=false

export CL2_WORKLOAD_TYPE="${CL2_WORKLOAD_TYPE:-replicaset}"
export CL2_MAX_SANDBOXES="${CL2_MAX_SANDBOXES:-35000}"
export CL2_BURST="${CL2_BURST:-5000}"
export CL2_TEST_NUM_NODES="${CL2_TEST_NUM_NODES:-720}"
export CL2_SANDBOX_DELAY_BETWEEN_ITERATIONS="${CL2_SANDBOX_DELAY_BETWEEN_ITERATIONS:-1s}"
export CL2_CHURN_ITERATIONS="${CL2_CHURN_ITERATIONS:-5}"

export CL2_NETWORK_POLICY_TYPE="Global"
export CL2_NETWORK_POLICY_INCLUDE_RANDOM_CIDR_RULES=false
export CL2_NUMBER_OF_RESOURCES_PER_SANDBOX=1

cd "${CL2_DIR}"

RESTART_CILIUM=false RESTART_KCP=false CL2_APPLY_CILIUM_CONFIG_EMERGENCY_OVERRIDE=false INITIAL_PROMETHEUS_SETUP=false CREATE_TEST_NODEPOOLS=false MACHINE_TYPE="e2-small" NUM_NODES=${CL2_TEST_NUM_NODES} bash "${TEST_CONFIG_DIR}/pre-test.sh" || true

echo "Systematically synchronizing CNI daemonsets across worker instances before benchmarking..."
if [[ "$CLUSTER_NAME" == *"netpol"* ]]; then
  kubectl rollout status daemonset kindnet -n kube-system --timeout=15m || true
elif [[ "$CLUSTER_NAME" == *"calico"* ]]; then
  kubectl rollout status daemonset calico-node -n kube-system --timeout=15m || true
elif [[ "$CLUSTER_NAME" == *"cilium"* ]]; then
  if [[ "${RESTART_CILIUM:-false}" == "true" ]]; then
    echo "Removing api-rate-limit overrides to benchmark raw Cilium speed..."
    kubectl patch configmap cilium-config -n kube-system --type=json -p='[{"op": "remove", "path": "/data/api-rate-limit"}]' || true
    kubectl rollout restart ds/cilium -n kube-system
    kubectl rollout status daemonset cilium -n kube-system --timeout=15m || true
  fi
elif [[ "$CLUSTER_NAME" == *"flannel"* ]]; then
  kubectl rollout status daemonset kube-flannel-ds -n kube-flannel --timeout=15m || true
  kubectl rollout status daemonset kube-network-policies -n kube-system --timeout=15m || true
fi


echo "Labeling the prometheus node so clusterloader2 can find it, bypassing kops quirks."
kubectl label nodes -l kops.k8s.io/instancegroup=prometheus-nodes prometheus-pool=true --overwrite || true

echo "Injecting node-to-master firewall rule for GCP because kops defaults block CNI metrics scraping..."
NETWORK_NAME="${CLUSTER_NAME//./-}"
if ! gcloud compute firewall-rules describe node-to-master-cni-metrics-${NETWORK_NAME} >/dev/null 2>&1; then
  gcloud compute firewall-rules create node-to-master-cni-metrics-${NETWORK_NAME} \
    --network ${NETWORK_NAME} \
    --allow tcp:9080,tcp:9091,tcp:9090,tcp:9962,tcp:9963,tcp:19080,tcp:4001,tcp:4002 \
    --source-tags ${NETWORK_NAME}-k8s-io-role-node \
    --target-tags ${NETWORK_NAME}-k8s-io-role-control-plane,${NETWORK_NAME}-k8s-io-role-master \
    --priority 1000 || true
fi


go run ./cmd/clusterloader.go \
      --kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}" \
      --testconfig="${TEST_CONFIG_DIR}/config.yaml" \
      --provider=gce \
      --nodes="${CL2_TEST_NUM_NODES}" \
      --v=2 \
      --enable-prometheus-server=true \
      --report-dir="${REPORT_DIR}" \
      --k8s-clients-number=20 \
      --prometheus-scrape-kube-state-metrics=true \
      --prometheus-scrape-node-local-dns=true \
      --prometheus-scrape-kubelets=true || true

bash "${TEST_CONFIG_DIR}/post-test.sh" || true
