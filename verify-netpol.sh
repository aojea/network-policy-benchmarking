#!/bin/bash
set -e

NAMESPACE="netpol-test"

echo "[*] Cleaning up any existing test namespace..."
kubectl delete namespace $NAMESPACE --ignore-not-found=true
kubectl create namespace $NAMESPACE

echo "[*] Creating server pod (nginx)..."
kubectl run server --namespace=$NAMESPACE --image=nginx:alpine --labels="app=server" --expose --port=80
echo "[*] Creating client pod (busybox)..."
kubectl run client --namespace=$NAMESPACE --image=busybox --labels="app=client" -- sleep 3600

echo "[*] Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=server --namespace=$NAMESPACE --timeout=60s
kubectl wait --for=condition=ready pod -l app=client --namespace=$NAMESPACE --timeout=60s

SERVER_IP=$(kubectl get pod server -n $NAMESPACE -o jsonpath='{.status.podIP}')
echo "[*] Server IP is $SERVER_IP"

echo "----------------------------------------------------"
echo "Test 1: Connection without network policies"
echo "Expected: SUCCEED"
echo "----------------------------------------------------"
if kubectl exec client -n $NAMESPACE -- wget -qO- --timeout=3 http://$SERVER_IP > /dev/null; then
    echo "✅ Test 1 Passed: Connection succeeded."
else
    echo "❌ Test 1 Failed: Connection blocked but no policies exist."
    exit 1
fi

echo ""
echo "[*] Applying Default Deny NetworkPolicy to server..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
EOF

echo "[*] Waiting 5 seconds for policy to propagate..."
sleep 5

echo "----------------------------------------------------"
echo "Test 2: Connection with deny policy"
echo "Expected: FAIL"
echo "----------------------------------------------------"
if kubectl exec client -n $NAMESPACE -- wget -qO- --timeout=3 http://$SERVER_IP > /dev/null; then
    echo "❌ Test 2 Failed: Connection succeeded but should have been BLOCKED."
    exit 1
else
    echo "✅ Test 2 Passed: Connection successfully blocked."
fi

echo ""
echo "[*] Applying Allow NetworkPolicy from client to server..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client
    ports:
    - protocol: TCP
      port: 80
EOF

echo "[*] Waiting 5 seconds for policy to propagate..."
sleep 5

echo "----------------------------------------------------"
echo "Test 3: Connection with explicit allow policy"
echo "Expected: SUCCEED"
echo "----------------------------------------------------"
if kubectl exec client -n $NAMESPACE -- wget -qO- --timeout=3 http://$SERVER_IP > /dev/null; then
    echo "✅ Test 3 Passed: Connection succeeded after applying allow policy."
else
    echo "❌ Test 3 Failed: Connection blocked despite allow policy."
    exit 1
fi

echo ""
echo "🎉 All tests passed! Network policy enforcement is working correctly."

echo "[*] Cleaning up..."
kubectl delete namespace $NAMESPACE
