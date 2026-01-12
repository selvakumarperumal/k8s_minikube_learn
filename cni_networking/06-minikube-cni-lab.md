# Chapter 6: Minikube CNI Labs 🔬

## Table of Contents

1. [Lab 1: Default CNI Exploration](#lab-1-default-cni-exploration)
2. [Lab 2: Installing Calico](#lab-2-installing-calico)
3. [Lab 3: Pod Networking Investigation](#lab-3-pod-networking-investigation)
4. [Lab 4: Cross-Node Communication](#lab-4-cross-node-communication)
5. [Lab 5: Network Troubleshooting](#lab-5-network-troubleshooting)
6. [Lab 6: CNI Plugin Comparison](#lab-6-cni-plugin-comparison)

---

## Lab 1: Default CNI Exploration

### Objective

Understand Minikube's default CNI configuration (kindnet).

### Steps

```bash
# Step 1: Start fresh Minikube
minikube delete
minikube start

# Step 2: Verify cluster is running
kubectl get nodes
kubectl get pods -n kube-system

# Step 3: Check CNI configuration
minikube ssh "cat /etc/cni/net.d/*"

# Expected output (kindnet):
# {
#   "cniVersion": "0.3.1",
#   "name": "kindnet",
#   "plugins": [
#     {
#       "type": "ptp",
#       "ipMasq": false,
#       "ipam": {
#         "type": "host-local",
#         "ranges": [[{"subnet": "10.244.0.0/24"}]]
#       }
#     }
#   ]
# }
```

### Verify CNI Binaries

```bash
# Step 4: List CNI plugins
minikube ssh "ls -la /opt/cni/bin/"

# Step 5: Check which CNI is being used
kubectl get pods -n kube-system -l k8s-app=kindnet

# Step 6: View kindnet logs
kubectl logs -n kube-system -l k8s-app=kindnet --tail=50
```

### Expected Results

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      LAB 1 EXPECTED RESULTS                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. CNI Config: /etc/cni/net.d/10-kindnet.conflist                      │
│  2. Plugin Type: ptp (point-to-point)                                    │
│  3. IPAM: host-local with subnet 10.244.0.0/24                          │
│  4. kindnet DaemonSet running in kube-system                             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Lab 2: Installing Calico

### Objective

Start Minikube with Calico CNI and explore its configuration.

### Steps

```bash
# Step 1: Delete existing cluster
minikube delete

# Step 2: Start with Calico
minikube start --cni=calico

# Step 3: Wait for Calico to be ready
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s

# Step 4: Verify Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Step 5: Check Calico CNI config
minikube ssh "cat /etc/cni/net.d/*calico*"
```

### Explore Calico Components

```bash
# Step 6: View Calico node status
kubectl exec -n kube-system -it $(kubectl get pod -n kube-system -l k8s-app=calico-node -o name | head -1) -- calico-node -show-status

# Step 7: View IP pools
kubectl get ippools -o yaml

# Step 8: Check BGP configuration (if available)
kubectl exec -n kube-system -it $(kubectl get pod -n kube-system -l k8s-app=calico-node -o name | head -1) -- birdcl show route

# Step 9: View felix logs
kubectl logs -n kube-system -l k8s-app=calico-node -c calico-node --tail=30
```

### Calico Network YAML Example

```yaml
# File: examples/calico-ippool.yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: custom-pool
spec:
  cidr: 10.100.0.0/16
  ipipMode: Always
  natOutgoing: true
  nodeSelector: all()
```

---

## Lab 3: Pod Networking Investigation

### Objective

Deep dive into how pods get their network configuration.

### Setup

```bash
# Step 1: Create test pods
kubectl create deployment web --image=nginx --replicas=3

# Step 2: Wait for pods
kubectl wait --for=condition=ready pod -l app=web --timeout=60s

# Step 3: Get pod IPs
kubectl get pods -o wide
```

### Investigate Network Namespaces

```bash
# Step 4: SSH into Minikube
minikube ssh

# Step 5: List network namespaces
sudo ip netns list

# Step 6: Pick a namespace and explore
NETNS=$(sudo ip netns list | head -1 | awk '{print $1}')

# View interfaces in namespace
sudo ip netns exec $NETNS ip addr

# View routes in namespace
sudo ip netns exec $NETNS ip route

# View ARP table
sudo ip netns exec $NETNS ip neigh
```

### Investigate veth Pairs

```bash
# Step 7: Find veth pairs on host
ip link show type veth

# Step 8: Show which bridge they connect to
bridge link show

# Step 9: Match pod interface to host veth
# Get interface index from a pod
kubectl exec $(kubectl get pods -l app=web -o name | head -1) -- cat /sys/class/net/eth0/iflink

# Find matching veth on host (look for index)
minikube ssh "ip link | grep <index>:"
```

### Diagram What You Found

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     YOUR LAB FINDINGS                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Pod: web-xxx-yyy                                                        │
│  ├── Namespace: cni-<uuid>                                              │
│  ├── Interface: eth0 (IP: 10.244.0.X)                                   │
│  └── Connected via veth pair to host                                    │
│                                                                          │
│  Host:                                                                   │
│  ├── vethXXXX connected to cni0 bridge                                  │
│  ├── cni0 bridge (IP: 10.244.0.1)                                       │
│  └── Routes to other nodes via flannel.1/tunl0                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Lab 4: Cross-Node Communication

### Objective

Observe pod-to-pod communication across nodes.

### Setup Multi-Node Cluster

```bash
# Step 1: Create multi-node cluster
minikube delete
minikube start --nodes 2 --cni=calico

# Step 2: Verify nodes
kubectl get nodes
```

### Create Pods on Different Nodes

```yaml
# File: examples/cross-node-pods.yaml
apiVersion: v1
kind: Pod
metadata:
  name: sender
  labels:
    app: sender
spec:
  nodeName: minikube
  containers:
  - name: alpine
    image: alpine
    command: ['sleep', '3600']
---
apiVersion: v1
kind: Pod
metadata:
  name: receiver
  labels:
    app: receiver  
spec:
  nodeName: minikube-m02
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
```

```bash
# Step 3: Apply pods
kubectl apply -f examples/cross-node-pods.yaml

# Step 4: Wait for pods
kubectl wait --for=condition=ready pod/sender pod/receiver --timeout=120s

# Step 5: Get IPs
kubectl get pods -o wide
```

### Test Connectivity

```bash
# Step 6: Test ping
RECEIVER_IP=$(kubectl get pod receiver -o jsonpath='{.status.podIP}')
kubectl exec sender -- ping -c 5 $RECEIVER_IP

# Step 7: Test HTTP
kubectl exec sender -- wget -qO- http://$RECEIVER_IP

# Step 8: Traceroute
kubectl exec sender -- traceroute $RECEIVER_IP
```

### Capture Traffic

```bash
# Step 9: SSH to first node
minikube ssh

# Step 10: Capture encapsulated traffic (for IPIP)
sudo tcpdump -i eth0 'ip proto 4' -n -c 10

# For VXLAN
# sudo tcpdump -i eth0 'udp port 8472' -n -c 10

# Step 11: In another terminal, generate traffic
kubectl exec sender -- ping -c 10 $RECEIVER_IP
```

---

## Lab 5: Network Troubleshooting

### Objective

Learn to debug common CNI issues.

### Common Issues and Fixes

```bash
# Issue 1: Pod stuck in ContainerCreating
kubectl describe pod <pod-name>
# Look for: "failed to set up sandbox container network"

# Debug steps:
minikube ssh "cat /var/log/calico/cni/cni.log"
kubectl logs -n kube-system -l k8s-app=calico-node -c calico-node

# Issue 2: Pods can't reach each other
# Check routes
minikube ssh "ip route"

# Check iptables
minikube ssh "sudo iptables -L -n -v"

# Issue 3: DNS not working
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes
```

### Diagnostic Commands Cheatsheet

```yaml
# File: examples/troubleshooting-commands.yaml
# This is a reference file, not a Kubernetes manifest

# CNI Configuration
check_cni_config: |
  minikube ssh "cat /etc/cni/net.d/*"
  minikube ssh "ls -la /opt/cni/bin/"

# Network Namespaces
check_namespaces: |
  minikube ssh "sudo ip netns list"
  minikube ssh "sudo ip netns exec <ns> ip addr"

# Bridge and Routing
check_networking: |
  minikube ssh "ip link show type bridge"
  minikube ssh "bridge link show"
  minikube ssh "ip route"

# iptables
check_iptables: |
  minikube ssh "sudo iptables -t nat -L -n"
  minikube ssh "sudo iptables -t filter -L -n"

# CNI Plugin Logs
check_logs: |
  kubectl logs -n kube-system -l k8s-app=calico-node --tail=100
  kubectl logs -n kube-system -l k8s-app=kindnet --tail=100

# Pod Network Debug
pod_debug: |
  kubectl exec <pod> -- ip addr
  kubectl exec <pod> -- ip route
  kubectl exec <pod> -- cat /etc/resolv.conf
```

---

## Lab 6: CNI Plugin Comparison

### Objective

Install different CNI plugins and compare behavior.

### Test Matrix

```bash
# Test 1: With Flannel
minikube delete
minikube start --cni=flannel
kubectl create deployment test --image=nginx --replicas=2
kubectl get pods -o wide
# Record: Pod IPs, startup time, CNI config

# Test 2: With Calico
minikube delete  
minikube start --cni=calico
kubectl create deployment test --image=nginx --replicas=2
kubectl get pods -o wide
# Record: Pod IPs, startup time, CNI config

# Test 3: With Cilium
minikube delete
minikube start --cni=cilium
kubectl create deployment test --image=nginx --replicas=2
kubectl get pods -o wide
# Record: Pod IPs, startup time, CNI config
```

### Comparison Table Template

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CNI COMPARISON RESULTS                               │
├──────────────┬──────────────┬──────────────┬──────────────┬─────────────┤
│ Feature      │ kindnet      │ Flannel      │ Calico       │ Cilium      │
├──────────────┼──────────────┼──────────────┼──────────────┼─────────────┤
│ Startup Time │ ____ sec     │ ____ sec     │ ____ sec     │ ____ sec    │
├──────────────┼──────────────┼──────────────┼──────────────┼─────────────┤
│ Pod CIDR     │              │              │              │             │
├──────────────┼──────────────┼──────────────┼──────────────┼─────────────┤
│ Encapsulation│              │              │              │             │
├──────────────┼──────────────┼──────────────┼──────────────┼─────────────┤
│ Net Policies │ ❌           │ ❌           │ ✅           │ ✅ (L7)     │
├──────────────┼──────────────┼──────────────┼──────────────┼─────────────┤
│ Config File  │              │              │              │             │
└──────────────┴──────────────┴──────────────┴──────────────┴─────────────┘
```

---

## Lab Solutions Reference

### Quick Setup Scripts

```bash
#!/bin/bash
# File: examples/setup-cni-lab.sh

# Clean start
minikube delete --all

# Start cluster based on argument
case $1 in
  "calico")
    minikube start --cni=calico --nodes 2
    kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
    ;;
  "flannel")
    minikube start --cni=flannel --nodes 2
    ;;
  "cilium")
    minikube start --cni=cilium --nodes 2
    kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
    ;;
  *)
    minikube start --nodes 2
    ;;
esac

# Create test pods
kubectl apply -f examples/cross-node-pods.yaml
kubectl wait --for=condition=ready pod/sender pod/receiver --timeout=120s

echo "Cluster ready! Run: kubectl get pods -o wide"
```

---

## Key Takeaways

> [!IMPORTANT]
> 1. **Always check** `/etc/cni/net.d/` for CNI configuration
> 2. **Network namespaces** isolate pod networking
> 3. **veth pairs** connect pods to the bridge
> 4. **tcpdump** helps observe encapsulated traffic
> 5. **Different CNIs** have different features and trade-offs

---

## What's Next?

You've completed the CNI Networking documentation! Here are some next steps:

- Apply network policies with your chosen CNI
- Explore service mesh integration
- Deep dive into Cilium's Hubble for observability
- Practice troubleshooting real networking issues

**[Back to README →](README.md)**
