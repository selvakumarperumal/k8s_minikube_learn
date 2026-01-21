# Networking Examples

This folder contains comprehensive YAML examples for each networking topic.

## File Overview

| File | Topic | Examples |
|------|-------|----------|
| [01-services-examples.yaml](01-services-examples.yaml) | Services | ClusterIP, NodePort, LoadBalancer, Headless, ExternalName, Multi-port, Session Affinity |
| [02-ingress-examples.yaml](02-ingress-examples.yaml) | Ingress | Path-based, Host-based, TLS, Rate Limiting, Auth, Headers |
| [03-network-policies-examples.yaml](03-network-policies-examples.yaml) | Network Policies | Deny-all, Allow specific, Namespace, CIDR, Egress |
| [04-dns-examples.yaml](04-dns-examples.yaml) | DNS | Policies, Custom DNS, Headless, StatefulSet |
| [05-istio-examples.yaml](05-istio-examples.yaml) | Istio | Gateway, VirtualService, DestinationRule, mTLS, Auth |
| [06-gateway-api-examples.yaml](06-gateway-api-examples.yaml) | Gateway API | HTTPRoute, Traffic Splitting, Header Routing, TLS, URL Rewrite |

## Quick Start

```bash
# Services (works on any cluster)
kubectl apply -f 01-services-examples.yaml

# Ingress (requires ingress controller)
minikube addons enable ingress
kubectl apply -f 02-ingress-examples.yaml

# Network Policies (requires Calico CNI)
minikube start --cni=calico
kubectl apply -f 03-network-policies-examples.yaml

# DNS (works on any cluster)
kubectl apply -f 04-dns-examples.yaml

# Istio (requires Istio installed)
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled
kubectl apply -f 05-istio-examples.yaml
```

## How to Use Each File

### 1. Services Examples

```bash
# Apply
kubectl apply -f 01-services-examples.yaml

# Test ClusterIP
kubectl run curl --image=curlimages/curl --rm -it -- curl http://web-clusterip

# Test NodePort
curl http://$(minikube ip):30080

# Test LoadBalancer
minikube tunnel  # In separate terminal
curl http://<EXTERNAL-IP>

# Test Headless
kubectl run dnstest --image=busybox --rm -it -- nslookup web-headless
```

### 2. Ingress Examples

```bash
# Enable ingress
minikube addons enable ingress

# Apply
kubectl apply -f 02-ingress-examples.yaml

# Add hosts
echo "$(minikube ip) demo.local api.local web.local admin.local" | sudo tee -a /etc/hosts

# Test
curl http://demo.local
curl http://api.local/api/
curl http://web.local
```

### 3. Network Policies Examples

```bash
# Start with Calico
minikube delete
minikube start --cni=calico

# Apply
kubectl apply -f 03-network-policies-examples.yaml

# Test before policies
kubectl exec -n netpol-demo frontend -- curl -s http://backend

# Apply deny-all
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: netpol-demo
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress: []
EOF

# Test after policies (should timeout)
kubectl exec -n netpol-demo frontend -- curl -s --max-time 3 http://backend
```

### 4. DNS Examples

```bash
# Apply
kubectl apply -f 04-dns-examples.yaml

# View DNS config
kubectl exec dns-default -- cat /etc/resolv.conf

# Test resolution
kubectl exec dns-default -- nslookup kubernetes
kubectl exec dns-default -- nslookup my-service
```

### 5. Istio Examples

```bash
# Install Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled

# Apply
kubectl apply -f 05-istio-examples.yaml

# Get ingress URL
export INGRESS_HOST=$(minikube ip)
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

# Test
curl http://$INGRESS_HOST:$INGRESS_PORT
```

### 6. Gateway API Examples

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Install NGINX Gateway Fabric controller
kubectl apply -f https://github.com/nginx/nginx-gateway-fabric/releases/download/v1.5.0/crds.yaml
kubectl apply -f https://github.com/nginx/nginx-gateway-fabric/releases/download/v1.5.0/nginx-gateway.yaml

# Wait for controller
kubectl wait --namespace nginx-gateway \
  --for=condition=Available deployment/nginx-gateway \
  --timeout=120s

# Apply examples
kubectl apply -f 06-gateway-api-examples.yaml

# Start tunnel (in separate terminal)
minikube tunnel

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway main-gateway -o jsonpath='{.status.addresses[0].value}')

# Add hosts
echo "$GATEWAY_IP demo.local api.local web.local admin.local canary.local" | sudo tee -a /etc/hosts

# Test
curl http://demo.local
curl http://api.local/api
curl http://canary.local  # Traffic splitting example

# Test header-based routing
curl -H "X-Version: v2" http://api.local/version
```

## Cleanup

```bash
# Delete all examples
kubectl delete -f 01-services-examples.yaml
kubectl delete -f 02-ingress-examples.yaml
kubectl delete -f 03-network-policies-examples.yaml
kubectl delete -f 04-dns-examples.yaml
kubectl delete -f 05-istio-examples.yaml
kubectl delete -f 06-gateway-api-examples.yaml

# Delete namespaces (for network policies)
kubectl delete namespace netpol-demo monitoring external

# Delete Gateway API CRDs (if no longer needed)
# kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```
