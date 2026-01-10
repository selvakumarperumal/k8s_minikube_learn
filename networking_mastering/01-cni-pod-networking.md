# Chapter 1: CNI & Pod-to-Pod Networking

## Table of Contents

1. [What is CNI?](#what-is-cni)
2. [Kubernetes Networking Model](#kubernetes-networking-model)
3. [How Pod Networking Works](#how-pod-networking-works)
4. [CNI Plugins Comparison](#cni-plugins-comparison)
5. [Network Namespaces](#network-namespaces)
6. [Hands-on Labs](#hands-on-labs)

---

## What is CNI?

### Definition

**CNI (Container Network Interface)** is a specification and a set of libraries for configuring network interfaces in Linux containers. It's the standard way Kubernetes sets up networking for pods.

```mermaid
flowchart TB
    subgraph CNIFlow["CNI Flow"]
        Kubelet["Kubelet"] -->|"1. Pod Created"| CNI["CNI Plugin"]
        CNI -->|"2. Create veth pair"| Veth["veth0 ↔ vethXXX"]
        Veth -->|"3. Attach to bridge"| Bridge["cni0 bridge"]
        Bridge -->|"4. Assign IP"| Pod["Pod gets IP"]
    end
    
    style Kubelet fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style CNI fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style Pod fill:#ffb86c,stroke:#f1fa8c,color:#282a36
```

### CNI Responsibilities

| Responsibility | Description |
|----------------|-------------|
| **IP Assignment** | Assign unique IP to each pod |
| **Network Interface** | Create network interface inside pod |
| **Routing** | Set up routes so pods can communicate |
| **Cleanup** | Remove network config when pod deleted |

---

## Kubernetes Networking Model

### The Four Fundamental Rules

Kubernetes networking is built on these rules:

```mermaid
flowchart TB
    subgraph Rules["Kubernetes Networking Rules"]
        R1["1️⃣ Every Pod gets its own unique IP address"]
        R2["2️⃣ Pods can communicate with any other Pod<br/>across any node WITHOUT NAT"]
        R3["3️⃣ Agents on a node (kubelet, etc) can<br/>communicate with all Pods on that node"]
        R4["4️⃣ Pod's IP is the same whether viewed<br/>from inside or outside the Pod"]
    end
    
    style R1 fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style R2 fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style R3 fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style R4 fill:#8be9fd,stroke:#50fa7b,color:#282a36
```

### What This Means

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
│                                                              │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │      Node 1         │    │      Node 2         │         │
│  │                     │    │                     │         │
│  │  ┌─────┐  ┌─────┐  │    │  ┌─────┐  ┌─────┐  │         │
│  │  │Pod A│  │Pod B│  │    │  │Pod C│  │Pod D│  │         │
│  │  │10.0.│  │10.0.│  │    │  │10.0.│  │10.0.│  │         │
│  │  │1.10 │  │1.11 │  │    │  │2.10 │  │2.11 │  │         │
│  │  └─────┘  └─────┘  │    │  └─────┘  └─────┘  │         │
│  │         ↕          │    │         ↕          │         │
│  │   ┌──────────┐    │    │   ┌──────────┐    │         │
│  │   │cni0 bridge│    │    │   │cni0 bridge│    │         │
│  │   │ 10.0.1.1 │    │    │   │ 10.0.2.1 │    │         │
│  │   └──────────┘    │    │   └──────────┘    │         │
│  │         ↕          │    │         ↕          │         │
│  │   Node: 192.168.1.10    │   Node: 192.168.1.11         │
│  └─────────────────────┘    └─────────────────────┘         │
│                    ↕                   ↕                     │
│               ┌────────────────────────────┐                │
│               │     Overlay Network /      │                │
│               │     Physical Network       │                │
│               └────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘

Pod A (10.0.1.10) can directly reach Pod C (10.0.2.10)
No NAT required - just routing!
```

---

## How Pod Networking Works

### Step-by-Step Pod Network Creation

When a pod is created, here's what happens:

```mermaid
sequenceDiagram
    participant API as API Server
    participant Sched as Scheduler
    participant Kubelet as Kubelet
    participant CNI as CNI Plugin
    participant Pod as Pod
    
    API->>Sched: 1. New pod created
    Sched->>API: 2. Assign to Node 1
    API->>Kubelet: 3. Create pod on Node 1
    Kubelet->>CNI: 4. Call CNI ADD
    
    Note over CNI: CNI does the following:
    CNI->>CNI: 5a. Create network namespace
    CNI->>CNI: 5b. Create veth pair
    CNI->>CNI: 5c. Move veth to pod namespace
    CNI->>CNI: 5d. Assign IP address
    CNI->>CNI: 5e. Set up routes
    
    CNI-->>Kubelet: 6. Return IP address
    Kubelet->>Pod: 7. Pod is ready!
```

### Virtual Ethernet (veth) Pairs

A veth pair is like a virtual network cable with two ends:

```
┌─────────────────────────────────────────────────────────────┐
│                          Node                                │
│                                                              │
│  ┌────────────────────────────┐                             │
│  │     Pod Network Namespace   │                             │
│  │                             │                             │
│  │   ┌─────────────────────┐  │                             │
│  │   │    eth0 (10.0.1.10) │  │  ← Pod sees this as eth0   │
│  │   └─────────┬───────────┘  │                             │
│  │             │               │                             │
│  └─────────────│───────────────┘                             │
│                │                                              │
│                │  veth pair (virtual cable)                   │
│                │                                              │
│  ┌─────────────│───────────────┐                             │
│  │     Host Network Namespace   │                             │
│  │             │               │                             │
│  │   ┌─────────┴───────────┐  │                             │
│  │   │  vethXXXX          │  │  ← Host end of veth         │
│  │   └─────────┬───────────┘  │                             │
│  │             │               │                             │
│  │   ┌─────────┴───────────┐  │                             │
│  │   │   cni0 bridge       │  │  ← All pod veths connect   │
│  │   │   10.0.1.1          │  │    to this bridge          │
│  │   └─────────────────────┘  │                             │
│  │                             │                             │
│  └─────────────────────────────┘                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Same Node Communication

When Pod A talks to Pod B on the same node:

```mermaid
flowchart LR
    subgraph Node["Node 1"]
        subgraph PodA["Pod A (10.0.1.10)"]
            AppA["App"] --> EthA["eth0"]
        end
        
        subgraph PodB["Pod B (10.0.1.11)"]
            EthB["eth0"] --> AppB["App"]
        end
        
        Bridge["cni0 bridge<br/>10.0.1.1"]
        
        EthA --> VethA["vethAAA"]
        VethA --> Bridge
        Bridge --> VethB["vethBBB"]
        VethB --> EthB
    end
    
    style Bridge fill:#50fa7b,stroke:#8be9fd,color:#282a36
```

**Flow:**
1. Pod A sends packet to 10.0.1.11
2. Packet goes through eth0 → vethAAA
3. vethAAA is connected to cni0 bridge
4. Bridge sees destination is also connected (vethBBB)
5. Packet forwarded to vethBBB → eth0 in Pod B

### Cross-Node Communication

When Pod A on Node 1 talks to Pod C on Node 2:

```mermaid
flowchart TB
    subgraph Node1["Node 1 (192.168.1.10)"]
        PodA["Pod A<br/>10.0.1.10"]
        Bridge1["cni0<br/>10.0.1.1"]
        PodA --> Bridge1
    end
    
    subgraph Node2["Node 2 (192.168.1.11)"]
        Bridge2["cni0<br/>10.0.2.1"]
        PodC["Pod C<br/>10.0.2.10"]
        Bridge2 --> PodC
    end
    
    subgraph Overlay["Overlay Network"]
        VXLAN["VXLAN / IPIP / BGP"]
    end
    
    Bridge1 --> VXLAN
    VXLAN --> Bridge2
    
    style VXLAN fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
```

**Flow:**
1. Pod A sends packet to 10.0.2.10 (Pod C)
2. Packet reaches cni0 bridge on Node 1
3. Bridge checks routing table - 10.0.2.0/24 is on Node 2
4. Packet encapsulated (VXLAN/IPIP) or routed (BGP)
5. Packet arrives at Node 2
6. Decapsulated and delivered to cni0 on Node 2
7. Bridge forwards to Pod C

---

## CNI Plugins Comparison

### Popular CNI Plugins

```mermaid
flowchart TB
    subgraph Plugins["CNI Plugins"]
        Calico["Calico<br/>⭐ Most Popular"]
        Flannel["Flannel<br/>Simple"]
        Cilium["Cilium<br/>eBPF-based"]
        Weave["Weave<br/>Mesh Network"]
        Canal["Canal<br/>Calico + Flannel"]
    end
    
    style Calico fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style Cilium fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
```

### Detailed Comparison

| Feature | Calico | Flannel | Cilium | Weave |
|---------|--------|---------|--------|-------|
| **Network Policies** | ✅ Full | ❌ No | ✅ L3-L7 | ✅ Basic |
| **Encryption** | ✅ WireGuard | ❌ No | ✅ IPsec/WireGuard | ✅ Built-in |
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Complexity** | Medium | Low | High | Low |
| **Observability** | Good | Basic | Excellent | Good |
| **Best For** | Production | Dev/Simple | High perf/Security | Multi-cloud |

### Calico Deep Dive

Calico is the most popular CNI for production:

```yaml
# Calico uses these modes:
# 1. IPIP (IP-in-IP tunneling) - Default
# 2. VXLAN (Virtual Extensible LAN)
# 3. BGP (Border Gateway Protocol) - No overlay

# Calico Architecture:
# 
# ┌─────────────────────────────────────────────┐
# │                  Node                        │
# │                                              │
# │  ┌─────────────────────────────────────┐   │
# │  │         calico-node DaemonSet        │   │
# │  │                                       │   │
# │  │  ┌─────────┐  ┌─────────┐           │   │
# │  │  │ Felix   │  │ BIRD    │           │   │
# │  │  │ (Agent) │  │ (BGP)   │           │   │
# │  │  └─────────┘  └─────────┘           │   │
# │  └─────────────────────────────────────┘   │
# │                                              │
# │  Pods...                                     │
# └─────────────────────────────────────────────┘
#
# Felix: Programs routes and network policies
# BIRD: Distributes routes via BGP
```

### Cilium Deep Dive

Cilium uses eBPF for high performance:

```
┌─────────────────────────────────────────────────────────────┐
│                     Cilium Architecture                      │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                    Linux Kernel                        │ │
│  │                                                        │ │
│  │   ┌─────────────────────────────────────────────────┐ │ │
│  │   │              eBPF Programs                       │ │ │
│  │   │                                                  │ │ │
│  │   │  ┌──────────┐ ┌──────────┐ ┌──────────┐        │ │ │
│  │   │  │ L3/L4    │ │Load      │ │Network   │        │ │ │
│  │   │  │ Routing  │ │Balancing │ │Policies  │        │ │ │
│  │   │  └──────────┘ └──────────┘ └──────────┘        │ │ │
│  │   └─────────────────────────────────────────────────┘ │ │
│  │                                                        │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                              │
│  Benefits:                                                   │
│  - No iptables (uses eBPF)                                  │
│  - L7 visibility (HTTP, gRPC, Kafka)                        │
│  - Identity-based policies                                   │
│  - Hubble for observability                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Network Namespaces

### What is a Network Namespace?

A network namespace is an isolated network stack with its own:
- Network interfaces
- Routing tables
- iptables rules
- Socket ports

```bash
# Each pod runs in its own network namespace
# You can see namespaces on the node:

# SSH into Minikube
minikube ssh

# List network namespaces
ip netns list

# Each pod has a namespace like: cni-xxxxx-xxxx-xxxx
```

### How Pods Get Isolated Networks

```
┌─────────────────────────────────────────────────────────────┐
│                        Host                                  │
│                                                              │
│  ┌─────────────────────┐  ┌─────────────────────┐          │
│  │ Network Namespace 1 │  │ Network Namespace 2 │          │
│  │     (Pod A)         │  │     (Pod B)         │          │
│  │                     │  │                     │          │
│  │  Interfaces:        │  │  Interfaces:        │          │
│  │  - eth0: 10.0.1.10  │  │  - eth0: 10.0.1.11  │          │
│  │  - lo: 127.0.0.1    │  │  - lo: 127.0.0.1    │          │
│  │                     │  │                     │          │
│  │  Routing table:     │  │  Routing table:     │          │
│  │  - default via      │  │  - default via      │          │
│  │    10.0.1.1         │  │    10.0.1.1         │          │
│  │                     │  │                     │          │
│  │  iptables: (own)    │  │  iptables: (own)    │          │
│  │  Ports: (own)       │  │  Ports: (own)       │          │
│  └─────────────────────┘  └─────────────────────┘          │
│                                                              │
│  Each pod thinks it has its own dedicated network!          │
└─────────────────────────────────────────────────────────────┘
```

---

## Hands-on Labs

### Lab 1: View Pod IPs

```bash
# Create multiple pods
kubectl create deployment web --image=nginx --replicas=3

# View pods with their IPs
kubectl get pods -o wide

# Output:
# NAME                   READY   STATUS    IP           NODE
# web-xxx-aaa           1/1     Running   10.0.1.10    minikube
# web-xxx-bbb           1/1     Running   10.0.1.11    minikube
# web-xxx-ccc           1/1     Running   10.0.1.12    minikube
```

### Lab 2: Test Pod-to-Pod Communication

```bash
# Create two pods
kubectl run sender --image=busybox --command -- sleep 3600
kubectl run receiver --image=nginx

# Get receiver's IP
RECEIVER_IP=$(kubectl get pod receiver -o jsonpath='{.status.podIP}')
echo "Receiver IP: $RECEIVER_IP"

# Test connectivity from sender to receiver
kubectl exec sender -- wget -qO- http://$RECEIVER_IP

# You should see nginx HTML!
```

### Lab 3: Explore CNI on Minikube

```bash
# SSH into Minikube
minikube ssh

# View bridges
ip link show type bridge

# View CNI config
cat /etc/cni/net.d/*

# View pod network interfaces
ip link show | grep veth

# View routing table
ip route

# Exit Minikube
exit
```

### Lab 4: View Network Namespaces

```bash
# SSH into Minikube
minikube ssh

# As root
sudo -i

# List network namespaces
ip netns list

# Pick a namespace (cni-xxxx-xxxx)
# View interfaces in that namespace
ip netns exec cni-xxxx-xxxx ip addr

# View routing in that namespace
ip netns exec cni-xxxx-xxxx ip route

exit
exit
```

### Lab 5: Use Different CNI

```bash
# Delete current Minikube
minikube delete

# Start with Calico
minikube start --cni=calico

# Verify Calico is running
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check Calico logs
kubectl logs -n kube-system -l k8s-app=calico-node -c calico-node --tail=20
```

---

## Key Takeaways

> [!IMPORTANT]
> 1. **Every pod gets a unique IP** - No port conflicts
> 2. **Pods communicate without NAT** - Direct routing
> 3. **CNI handles all setup** - Creates interfaces, assigns IPs
> 4. **veth pairs connect pods to bridge** - Virtual network cables
> 5. **Overlay networks handle cross-node** - VXLAN, IPIP, or BGP

---

## Next: [Chapter 2 - Services Deep Dive →](02-services-deep-dive.md)
