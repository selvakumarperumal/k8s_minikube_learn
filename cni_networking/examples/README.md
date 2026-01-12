# CNI Networking Examples 📁

This folder contains YAML examples for CNI networking concepts.

## Files

| File | Description |
|------|-------------|
| [00-cni-config-examples.yaml](00-cni-config-examples.yaml) | CNI configuration reference examples |
| [01-pod-networking-demos.yaml](01-pod-networking-demos.yaml) | Pod networking demonstration |
| [02-network-policies.yaml](02-network-policies.yaml) | Network policy examples |

## Usage

```bash
# Apply any example
kubectl apply -f <filename>.yaml

# Delete resources
kubectl delete -f <filename>.yaml
```

## Prerequisites

- Minikube with CNI (Calico recommended for network policies)
- kubectl configured

```bash
# Start Minikube with Calico
minikube start --cni=calico

# Verify CNI
kubectl get pods -n kube-system -l k8s-app=calico-node
```
