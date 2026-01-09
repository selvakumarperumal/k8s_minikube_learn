# Istio Service Mesh - Mastering Guide

A comprehensive guide to understanding and mastering Istio service mesh on Kubernetes.

## 📚 Documentation

| File | Topic | Description |
|------|-------|-------------|
| [01-introduction.md](01-introduction.md) | Introduction | What is Istio, why service mesh |
| [02-architecture.md](02-architecture.md) | Architecture | Control plane, data plane, components |
| [03-traffic-management.md](03-traffic-management.md) | Traffic Management | VirtualService, DestinationRule, Gateway |
| [04-security.md](04-security.md) | Security | mTLS, authorization, authentication |
| [05-observability.md](05-observability.md) | Observability | Kiali, Jaeger, Prometheus, Grafana |
| [06-resiliency.md](06-resiliency.md) | Resiliency | Retries, timeouts, circuit breakers |

## 🚀 Quick Start

```bash
# 1. Install Istio on Minikube
minikube start --memory=8192 --cpus=4
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=demo -y

# 2. Enable sidecar injection for default namespace
kubectl label namespace default istio-injection=enabled

# 3. Verify installation
kubectl get pods -n istio-system
istioctl analyze
```

## 📁 Examples

All example YAML files are in the `examples/` directory:

```bash
# Apply examples
kubectl apply -f examples/01-gateway-example.yaml
kubectl apply -f examples/02-virtualservice-example.yaml
```

## 🎯 Learning Path

```mermaid
flowchart LR
    A[Introduction] --> B[Architecture]
    B --> C[Traffic Management]
    C --> D[Security]
    D --> E[Observability]
    E --> F[Resiliency]
    
    style A fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style B fill:#bd93f9,stroke:#ff79c6,color:#f8f8f2
    style C fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style D fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style E fill:#8be9fd,stroke:#50fa7b,color:#282a36
    style F fill:#f1fa8c,stroke:#ffb86c,color:#282a36
```
