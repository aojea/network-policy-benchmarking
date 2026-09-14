#!/bin/bash

if [ -z "${CLUSTER_NAME}" ]; then
  echo "Error: Need to set CLUSTER_NAME before running."
  echo "Usage: CLUSTER_NAME=agentic-netpol.k8s.local ./teardown-cluster.sh"
  exit 1
fi

export KOPS_STATE_STORE="${KOPS_STATE_STORE:-gs://kops-maspinwall-state}"
KOPS_BIN="${KOPS_BIN:-kops}"

# Determine CNI suffix from cluster name
if [[ "$CLUSTER_NAME" == *"netpol"* ]]; then
    CNI_TYPE="netpol"
elif [[ "$CLUSTER_NAME" == *"calico"* ]]; then
    CNI_TYPE="calico"
elif [[ "$CLUSTER_NAME" == *"cilium"* ]]; then
    CNI_TYPE="cilium"
else
    echo "Warning: Could not determine CNI type from cluster name."
fi

if [ -n "$CNI_TYPE" ]; then
    FW_NAME="node-to-master-cni-metrics-${CNI_TYPE}"
    echo "Ensuring out-of-band firewall rule ${FW_NAME} is deleted..."
    gcloud compute firewall-rules delete "${FW_NAME}" --quiet || true
fi

echo "Deleting Kops cluster: ${CLUSTER_NAME}..."
${KOPS_BIN} delete cluster --name="${CLUSTER_NAME}" --state="${KOPS_STATE_STORE}" --yes

echo "Teardown complete."
