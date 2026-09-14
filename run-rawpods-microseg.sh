#!/bin/bash
set -ex

echo "==================================================================="
echo "Running 35,000 Raw Pods (1:1 Identity, Bypassing ReplicaSets) at 500 QPS"
echo "==================================================================="

export CL2_QPS=500
export CL2_WORKLOAD_TYPE="pod"
export CL2_NETWORK_POLICY_TYPE="Global"
export CL2_BURST=5000
export REPORT_TAG="QPS500_35000identities_rawpods_microseg"
export RESTART_CILIUM=false

./run-test.sh
