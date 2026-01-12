# Chapter 2: CNI Architecture 🏗️

## Table of Contents

1. [Kubernetes & CNI Integration](#kubernetes--cni-integration)
2. [Kubelet CNI Flow](#kubelet-cni-flow)
3. [Container Runtime Integration](#container-runtime-integration)
4. [Pod Sandbox Networking](#pod-sandbox-networking)
5. [Network Namespace Lifecycle](#network-namespace-lifecycle)

---

## Kubernetes & CNI Integration

### How Kubernetes Uses CNI

```mermaid
flowchart TB
    subgraph ControlPlane["Control Plane"]
        API["API Server"]
        Scheduler["Scheduler"]
    end
    
    subgraph Node["Worker Node"]
        Kubelet["Kubelet"]
        CRI["Container Runtime\n(containerd)"]
        CNI["CNI Plugin"]
        
        subgraph Pods["Pods"]
            P1["Pod A"]
            P2["Pod B"]
        end
    end
    
    API --> Kubelet
    Kubelet --> CRI
    CRI --> CNI
    CNI --> Pods
    
    style ControlPlane fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style Node fill:#50fa7b,stroke:#8be9fd,color:#282a36
```

### The Integration Points

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES CNI INTEGRATION                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. CONFIGURATION                                                        │
│     Kubelet reads: /etc/cni/net.d/*.conf, *.conflist                   │
│     Kubelet finds: /opt/cni/bin/<plugin-name>                          │
│                                                                          │
│  2. KUBELET PARAMETERS                                                   │
│     --network-plugin=cni                                                 │
│     --cni-conf-dir=/etc/cni/net.d                                       │
│     --cni-bin-dir=/opt/cni/bin                                          │
│                                                                          │
│  3. FLOW                                                                 │
│     Pod Created → Kubelet → CRI → CNI ADD → Pod has network            │
│     Pod Deleted → Kubelet → CRI → CNI DEL → Network cleaned up         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Kubelet CNI Flow

### Pod Creation Sequence

```mermaid
sequenceDiagram
    participant API as API Server
    participant Sched as Scheduler
    participant Kubelet as Kubelet
    participant CRI as containerd
    participant CNI as CNI Plugin
    participant Pod as Pod
    
    API->>Sched: 1. New Pod created
    Sched->>API: 2. Assign to Node
    API->>Kubelet: 3. Watch detects Pod
    
    Kubelet->>CRI: 4. RunPodSandbox()
    Note over CRI: Create pause container
    CRI->>CRI: 5. Create network namespace
    
    CRI->>CNI: 6. CNI ADD
    Note over CNI: Create veth, bridge, IP
    CNI-->>CRI: 7. Return IPs, routes
    
    CRI-->>Kubelet: 8. Sandbox ready
    
    Kubelet->>CRI: 9. CreateContainer()
    Kubelet->>CRI: 10. StartContainer()
    
    Pod->>Pod: 11. Pod Running!
```

### Detailed Step Breakdown

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         POD CREATION STEPS                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  STEP 1-3: SCHEDULING                                                    │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │ API Server  │───▶│  Scheduler  │───▶│   Kubelet   │                 │
│  │ stores pod  │    │ picks node  │    │ gets event  │                 │
│  └─────────────┘    └─────────────┘    └─────────────┘                 │
│                                                                          │
│  STEP 4-7: SANDBOX CREATION                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │   Kubelet   │───▶│ containerd  │───▶│ CNI Plugin  │                 │
│  │  calls CRI  │    │creates netns│    │ configures  │                 │
│  │             │    │             │    │  network    │                 │
│  └─────────────┘    └─────────────┘    └─────────────┘                 │
│                                              │                           │
│                                              ▼                           │
│  STEP 8-11: CONTAINER START          ┌─────────────────┐               │
│  ┌─────────────┐                     │ IP: 10.0.1.5    │               │
│  │   Kubelet   │────────────────────▶│ Routes: ✓      │               │
│  │starts conts │                     │ DNS: ✓         │               │
│  └─────────────┘                     │ Pod Running!   │               │
│                                      └─────────────────┘               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Container Runtime Integration

### CRI and CNI Relationship

```mermaid
flowchart TB
    subgraph K8s["Kubernetes"]
        Kubelet["Kubelet"]
    end
    
    subgraph CRI_Layer["CRI (Container Runtime Interface)"]
        CRI["CRI API"]
        CD["containerd"]
        CRIO["CRI-O"]
    end
    
    subgraph CNI_Layer["CNI Layer"]
        CNI["CNI Plugins"]
    end
    
    Kubelet -->|"gRPC calls"| CRI
    CRI --> CD
    CRI --> CRIO
    CD -->|"Calls CNI"| CNI
    CRIO -->|"Calls CNI"| CNI
    
    style K8s fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style CRI_Layer fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style CNI_Layer fill:#f1fa8c,stroke:#ffb86c,color:#282a36
```

### containerd CNI Integration

```yaml
# containerd config.toml CNI section
# Location: /etc/containerd/config.toml

[plugins."io.containerd.grpc.v1.cri".cni]
  # CNI binary directory
  bin_dir = "/opt/cni/bin"
  
  # CNI configuration directory
  conf_dir = "/etc/cni/net.d"
  
  # Maximum number of concurrent CNI calls
  max_conf_num = 1
  
  # CNI configuration file template
  conf_template = ""
```

---

## Pod Sandbox Networking

### What is a Pod Sandbox?

The Pod sandbox is the foundation for pod networking. It's created by the "pause" container.

```mermaid
flowchart TB
    subgraph Pod["Pod"]
        subgraph Sandbox["Pod Sandbox (pause container)"]
            NetNS["Network Namespace"]
            IPC["IPC Namespace"]
            PID["PID Namespace (shared)"]
        end
        
        C1["Container 1\n(app)"]
        C2["Container 2\n(sidecar)"]
        
        C1 --> Sandbox
        C2 --> Sandbox
    end
    
    style Sandbox fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style Pod fill:#f1fa8c,stroke:#ffb86c,color:#282a36
```

### Pause Container Role

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PAUSE CONTAINER                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Purpose: Hold namespaces for the pod                                    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         POD                                      │   │
│  │  ┌─────────────────────────────────────────────────────────────┐│   │
│  │  │                  PAUSE CONTAINER                            ││   │
│  │  │                                                              ││   │
│  │  │  Network Namespace: Contains eth0, IP address, routes       ││   │
│  │  │  IPC Namespace: Shared memory, semaphores                   ││   │
│  │  │  PID Namespace: Process isolation                           ││   │
│  │  │                                                              ││   │
│  │  └─────────────────────────────────────────────────────────────┘│   │
│  │                           ▲         ▲                           │   │
│  │                           │         │                           │   │
│  │  ┌──────────────────┐    │         │    ┌──────────────────┐  │   │
│  │  │   App Container   │────┘         └────│ Sidecar Container│  │   │
│  │  │   Joins pause's   │                   │   Joins pause's   │  │   │
│  │  │   namespaces      │                   │   namespaces      │  │   │
│  │  └──────────────────┘                   └──────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Benefits:                                                               │
│  • Containers share network (localhost works)                           │
│  • Containers share IPC (shared memory works)                           │
│  • Pod survives container restarts                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Multi-Container Pod Networking

```yaml
# Example: Multi-container pod sharing network namespace
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-pod
spec:
  containers:
  - name: web
    image: nginx:1.21
    ports:
    - containerPort: 80
  - name: sidecar
    image: busybox
    command: ['sh', '-c', 'while true; do wget -q -O- localhost:80; sleep 5; done']
    # Can access web on localhost because they share network namespace!
```

---

## Network Namespace Lifecycle

### Creation Flow

```mermaid
sequenceDiagram
    participant CRI as containerd
    participant NS as Namespace
    participant CNI as CNI Plugin
    
    Note over CRI,CNI: Pod Sandbox Creation
    
    CRI->>NS: 1. Create network namespace
    Note over NS: /var/run/netns/cni-xxxx
    
    CRI->>CNI: 2. CNI ADD with namespace path
    
    CNI->>NS: 3. Create veth pair
    Note over NS: veth0 in pod ns
    Note over NS: vethXXX on host
    
    CNI->>NS: 4. Configure interface
    Note over NS: IP, routes, DNS
    
    CNI-->>CRI: 5. Return configuration
```

### Namespace Persistence

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     NETWORK NAMESPACE LIFECYCLE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CREATION:                                                               │
│  ┌─────────────────┐                                                    │
│  │ Pod Scheduled   │                                                    │
│  │       ↓         │                                                    │
│  │ Create netns    │  →  /var/run/netns/cni-abc123                     │
│  │       ↓         │                                                    │
│  │ CNI configures  │  →  veth pair, IP, routes                         │
│  │       ↓         │                                                    │
│  │ Containers join │  →  All containers share netns                    │
│  └─────────────────┘                                                    │
│                                                                          │
│  PERSISTENCE:                                                            │
│  • Namespace exists as long as pause container runs                     │
│  • Survives app container crashes and restarts                          │
│  • Pod IP remains stable                                                │
│                                                                          │
│  DELETION:                                                               │
│  ┌─────────────────┐                                                    │
│  │ Pod Deleted     │                                                    │
│  │       ↓         │                                                    │
│  │ CNI DEL called  │  →  Remove veth, release IP                       │
│  │       ↓         │                                                    │
│  │ Remove netns    │  →  /var/run/netns/cni-abc123 deleted             │
│  └─────────────────┘                                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Viewing Namespaces in Minikube

```bash
# SSH into Minikube
minikube ssh

# List network namespaces (as root)
sudo ip netns list

# Example output:
# cni-12345678-90ab-cdef-1234-567890abcdef
# cni-abcdefgh-ijkl-mnop-qrst-uvwxyz123456

# View interfaces in a namespace
sudo ip netns exec cni-12345678-90ab-cdef-1234-567890abcdef ip addr

# View routes in a namespace
sudo ip netns exec cni-12345678-90ab-cdef-1234-567890abcdef ip route
```

---

## Key Takeaways

> [!IMPORTANT]
> 1. **Kubelet orchestrates** pod creation via CRI → CNI
> 2. **Pause container** holds the network namespace
> 3. **All pod containers** share the same network namespace
> 4. **CNI is called** during sandbox creation, not container start
> 5. **Namespace survives** container restarts

---

**[Next: Chapter 3 - CNI Plugins Deep Dive →](03-cni-plugins-deep-dive.md)**
