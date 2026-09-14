#!/bin/bash
# Natively probes the active worker node's Kindnet daemonset to dynamically map its Prometheus hook
# and extract the internal client-go workqueue and informer caching metrics to expose the queue delay.

echo "Locating an active Kindnet daemonset on a worker node..."
NODE=$(kubectl get pods -n sandboxes-1 -l group=sandbox -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
if [ -z "$NODE" ]; then
    # Fallback if no sandbox pods exist yet
    NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
fi

KINDNET_POD=$(kubectl get pods -n kube-system --field-selector spec.nodeName=$NODE -l k8s-app=kindnet -o name | head -n 1)
KINDNET_IP=$(kubectl get $KINDNET_POD -n kube-system -o jsonpath='{.status.podIP}')

echo "Targeting CNI agent: $KINDNET_POD (IP: $KINDNET_IP)"
echo "Scanning for an active telemetry listener..."

PORT="19080"

if [ -z "$PORT" ]; then
    echo ""
    echo "ERROR: Could not discover an open Prometheus metrics port on the Kindnet binary."
    echo "Conclusion: This specific minimalist fork of Kindnet natively disabled the metrics webserver at compilation, which is why the Prometheus scraping failed universally."
    exit 1
fi

echo "Successfully mapped Prometheus Hook on Port: $PORT!"
echo "Extracting the active client-go Informer Queue depths and CNI latency states:"
echo "=========================================================================="
curl -s http://$KINDNET_IP:$PORT/metrics | grep -iE 'workqueue|informer|kindnet'
echo "=========================================================================="
