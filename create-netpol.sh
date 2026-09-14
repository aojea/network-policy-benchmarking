#!/bin/bash
set -ex
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

export KOPS_STATE_STORE="${KOPS_STATE_STORE:-gs://kops-maspinwall-state}"
KOPS_BIN="${KOPS_BIN:-kops}"
CLUSTER_NAME="${CLUSTER_NAME:-agentic-netpol.k8s.local}"

${KOPS_BIN} create cluster \
  --name=${CLUSTER_NAME} \
  --zones=us-east1-b,us-east1-c,us-east1-d \
  --master-count=1 \
  --master-size=c4-standard-96 \
  --node-count=720 \
  --node-size=n2-standard-4 \
  --node-volume-size=50 \
  --topology=private \
  --networking=kindnet \
  --admin-access=0.0.0.0/0 \
  --kubernetes-version=1.36.2 \
  --set spec.etcdClusters[*].etcdMembers[*].volumeType=hyperdisk-balanced \
  --set spec.etcdClusters[*].etcdMembers[*].volumeIOPS=10000 \
  --set spec.etcdClusters[*].etcdMembers[*].volumeThroughput=1000 \
  --set spec.kubeControllerManager.kubeAPIQPS=500 \
  --set spec.kubeControllerManager.kubeAPIBurst=1000 \
  --set spec.kubeScheduler.qps=500 \
  --set spec.kubeScheduler.burst=1000 \
  --set spec.kubeAPIServer.eventTTL=5m \
  --set spec.etcdClusters[*].etcdMembers[*].volumeSize=120 \
  --dry-run \
  -o yaml > ${CLUSTER_NAME}.yaml

python3 patch_yaml.py ${CLUSTER_NAME}.yaml

${KOPS_BIN} replace -f ${CLUSTER_NAME}.yaml --force
${KOPS_BIN} update cluster --name=${CLUSTER_NAME} --yes --admin

echo "Cluster creation started. Waiting for 25m..."
${KOPS_BIN} validate cluster --name=${CLUSTER_NAME} --wait 25m

echo "Deploying kube-network-policies daemonset..."
# kubectl apply -f "${DIR}/manifests/kube-network-policies-install.yaml"

echo "Dynamically patching Kindnet daemonset to firmly mount the containerd NRI hostpath socket into the CNI namespace..."
cat << 'EOF' > /tmp/kindnet-nri-patch.yaml
spec:
  template:
    spec:
      containers:
      - name: kindnet-cni
        image: registry.k8s.io/networking/kindnet:v1.0.1
        volumeMounts:
        - mountPath: /var/run/nri
          name: nri-plugin
      volumes:
      - name: nri-plugin
        hostPath:
          path: /var/run/nri
          type: DirectoryOrCreate
EOF
kubectl patch ds kindnet -n kube-system --patch-file /tmp/kindnet-nri-patch.yaml --type=merge || true
kubectl rollout status ds kindnet -n kube-system || true

echo "Done! The cluster is ready."
echo "Sleeping for 5 minutes to allow the data-plane to stabilize before benchmarks..."
sleep 300
echo "Cluster fully stabilized."
