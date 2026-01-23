# Ingress Examples

Complete Ingress configurations with backend Deployments, Services, and detailed explanations.

## Files

| File | Explanation | Topic | Description |
|------|-------------|-------|-------------|
| [01_path_based.yaml](01_path_based.yaml) | [📖 Explained](01_path_based_explained.md) | Path-Based Routing | Route `/api/*`, `/web/*` to different services |
| [02_host_based.yaml](02_host_based.yaml) | [📖 Explained](02_host_based_explained.md) | Host-Based Routing | Route different hostnames to different services |
| [03_tls_ingress.yaml](03_tls_ingress.yaml) | [📖 Explained](03_tls_ingress_explained.md) | TLS/HTTPS | SSL termination, HTTP→HTTPS redirect, HSTS |
| [04_rate_limiting.yaml](04_rate_limiting.yaml) | [📖 Explained](04_rate_limiting_explained.md) | Rate Limiting & Security | RPS limits, IP whitelist, basic auth, custom headers |

## Quick Start

```bash
# 1. Enable Ingress addon
minikube addons enable ingress

# 2. Wait for controller
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 3. Apply an example
kubectl apply -f 01_path_based.yaml

# 4. Add to /etc/hosts
echo "$(minikube ip) myapp.example.com" | sudo tee -a /etc/hosts

# 5. Test
curl http://myapp.example.com/api/users
curl http://myapp.example.com/web/home
```

## Request Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Ingress Request Flow                     │
│                                                              │
│   1. Client sends: http://myapp.example.com/api/users        │
│                           │                                  │
│   2. DNS resolves to Ingress Controller IP                   │
│                           │                                  │
│   3. Ingress Controller receives request                     │
│      - Reads Host header                                     │
│      - Matches Ingress rules                                 │
│                           │                                  │
│   4. Applies annotations (rewrite, rate limit, etc.)         │
│                           │                                  │
│   5. Forwards to backend Service                             │
│                           │                                  │
│   6. Service load balances to Pod                            │
│                           │                                  │
│   7. Response returns via same path                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Cleanup

```bash
kubectl delete -f 01_path_based.yaml
kubectl delete -f 02_host_based.yaml
kubectl delete -f 03_tls_ingress.yaml
kubectl delete -f 04_rate_limiting.yaml
```
