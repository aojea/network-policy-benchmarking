#!/bin/bash
set -ex

QPS_VALUES=(500)
MASTER_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')

PROJECT="${PROJECT:-gke-maspinwall-dev-2}"
CLUSTER_ZONE="${CLUSTER_ZONE:-us-east1-b}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for qps in "${QPS_VALUES[@]}"; do
    burst=$((qps * 2))

    echo "========================================="
    echo "Turbo-charging KCM for cleanup..."
    echo "========================================="
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo sed -i 's/--kube-api-qps=[0-9]*/--kube-api-qps=2000/' /etc/kubernetes/manifests/kube-controller-manager.manifest"
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo sed -i 's/--kube-api-burst=[0-9]*/--kube-api-burst=4000/' /etc/kubernetes/manifests/kube-controller-manager.manifest"
    sleep 20
    
    echo "Deleting sandboxes-1 if it exists and waiting for termination..."
    kubectl delete namespace sandboxes-1 --ignore-not-found=true
    kubectl wait --for=delete namespace/sandboxes-1 --timeout=15m || true
    
    echo "========================================="
    echo "Setting QPS to $qps on $MASTER_NODE..."
    echo "========================================="
    
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo sed -i 's/--kube-api-qps=[0-9]*/--kube-api-qps=${qps}/' /etc/kubernetes/manifests/kube-controller-manager.manifest"
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo sed -i 's/--kube-api-burst=[0-9]*/--kube-api-burst=${burst}/' /etc/kubernetes/manifests/kube-controller-manager.manifest"
    
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo sed -i 's/qps: [0-9]*/qps: ${qps}/' /var/lib/kube-scheduler/config.yaml"
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo sed -i 's/burst: [0-9]*/burst: ${burst}/' /var/lib/kube-scheduler/config.yaml"
    
    # Touch the scheduler manifest to trigger a restart
    gcloud compute ssh ubuntu@${MASTER_NODE} --zone "${CLUSTER_ZONE}" --project "${PROJECT}" --command "sudo touch /etc/kubernetes/manifests/kube-scheduler.manifest"

    echo "Waiting for all worker nodes to be Ready..."
    sleep 30
    
    echo "Running benchmark for QPS $qps..."
    export CL2_QPS=$qps
    "${DIR}/run-test.sh"
    
    echo "Finished benchmark for QPS $qps"
done
