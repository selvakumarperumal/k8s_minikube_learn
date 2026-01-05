# PostgreSQL StatefulSet Deployment Flow

This document explains what happens step-by-step when you run:

```bash
kubectl apply -f statefulset-postgresql.yaml
```

---

## Overview: What Gets Created

```mermaid
graph TB
    subgraph CMD_BOX["⚡ kubectl apply -f statefulset-postgresql.yaml"]
        CMD[kubectl apply]
    end
    
    CMD --> SVC1[Service: postgres<br/>Headless]
    CMD --> SVC2[Service: postgres-lb<br/>ClusterIP]
    CMD --> CM[ConfigMap: postgres-config]
    CMD --> SEC[Secret: postgres-secret]
    CMD --> STS[StatefulSet: postgres]
    
    STS --> POD0[Pod: postgres-0]
    STS --> POD1[Pod: postgres-1]
    STS --> POD2[Pod: postgres-2]
    
    STS --> PVC0[PVC: postgres-storage-postgres-0]
    STS --> PVC1[PVC: postgres-storage-postgres-1]
    STS --> PVC2[PVC: postgres-storage-postgres-2]
    
    style CMD fill:#8be9fd,stroke:#6272a4,color:#282a36
    style SVC1 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style SVC2 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style CM fill:#bd93f9,stroke:#6272a4,color:#282a36
    style SEC fill:#ff79c6,stroke:#6272a4,color:#282a36
    style STS fill:#50fa7b,stroke:#6272a4,color:#282a36
    style POD0 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style POD1 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style POD2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style PVC0 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style PVC1 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style PVC2 fill:#f1fa8c,stroke:#6272a4,color:#282a36
```

---

## Step 1: API Server Receives the Request

```mermaid
sequenceDiagram
    participant User
    participant kubectl
    participant APIServer as API Server
    participant etcd
    
    User->>kubectl: kubectl apply -f statefulset-postgresql.yaml
    kubectl->>APIServer: POST /apis/v1/services<br/>POST /apis/apps/v1/statefulsets
    APIServer->>etcd: Store resource definitions
    etcd-->>APIServer: Acknowledged
    APIServer-->>kubectl: Resources created
    kubectl-->>User: service/postgres created<br/>statefulset/postgres created
```

---

## Step 2: StatefulSet Controller Takes Action

```mermaid
flowchart TD
    subgraph CP["🎛️ Control Plane"]
        STS_CTRL[StatefulSet Controller]
        SCHED[Scheduler]
    end
    
    subgraph ETCD["💾 etcd"]
        STS_DEF[StatefulSet Definition<br/>replicas: 3]
    end
    
    STS_CTRL -->|Watches| STS_DEF
    STS_CTRL -->|"Current Pods: 0<br/>Desired Pods: 3<br/>Need to create!"| CREATE
    
    CREATE[Create Pod postgres-0]
    CREATE --> SCHED
    SCHED -->|Assign to Node| NODE[Worker Node]
    
    style STS_CTRL fill:#8be9fd,stroke:#6272a4,color:#282a36
    style SCHED fill:#bd93f9,stroke:#6272a4,color:#282a36
    style STS_DEF fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style CREATE fill:#50fa7b,stroke:#6272a4,color:#282a36
    style NODE fill:#ffb86c,stroke:#6272a4,color:#282a36
```

---

## Step 3: Sequential Pod Creation (OrderedReady)

This is the KEY difference from Deployments. Pods are created **one at a time**, waiting for each to be Ready.

```mermaid
sequenceDiagram
    participant STS as StatefulSet Controller
    participant Node as Worker Node
    participant PVC as PVC Controller
    
    Note over STS: Start with 0 pods, need 3
    
    STS->>PVC: Create PVC: postgres-storage-postgres-0
    PVC-->>STS: PVC Bound
    STS->>Node: Create Pod: postgres-0
    Node-->>STS: Pod Running
    Note over Node: Wait for Readiness Probe...
    Node-->>STS: Pod Ready ✓
    
    Note over STS: 1 pod ready, need 3
    
    STS->>PVC: Create PVC: postgres-storage-postgres-1
    PVC-->>STS: PVC Bound
    STS->>Node: Create Pod: postgres-1
    Node-->>STS: Pod Running
    Note over Node: Wait for Readiness Probe...
    Node-->>STS: Pod Ready ✓
    
    Note over STS: 2 pods ready, need 3
    
    STS->>PVC: Create PVC: postgres-storage-postgres-2
    PVC-->>STS: PVC Bound
    STS->>Node: Create Pod: postgres-2
    Node-->>STS: Pod Running
    Note over Node: Wait for Readiness Probe...
    Node-->>STS: Pod Ready ✓
    
    Note over STS: 3 pods ready ✓ Done!
```

---

## Step 4: Container Startup Inside Each Pod

```mermaid
flowchart TD
    subgraph POD["🟢 Pod: postgres-0"]
        INIT[Container Starts]
        ENV[Load Environment Variables]
        MOUNT[Mount PVC at /var/lib/postgresql/data]
        PG_START[PostgreSQL Initializes]
        READY[Readiness Probe Passes]
    end
    
    INIT --> ENV
    ENV --> MOUNT
    MOUNT --> PG_START
    PG_START -->|pg_isready succeeds| READY
    
    subgraph ENVS["⚙️ Environment Variables Loaded"]
        E1[POSTGRES_DB=mydb]
        E2[POSTGRES_USER=admin]
        E3[POSTGRES_PASSWORD=supersecret123]
        E4[PGDATA=/var/lib/postgresql/data/pgdata]
    end
    
    ENV -.-> E1
    ENV -.-> E2
    ENV -.-> E3
    ENV -.-> E4
    
    style INIT fill:#8be9fd,stroke:#6272a4,color:#282a36
    style ENV fill:#bd93f9,stroke:#6272a4,color:#282a36
    style MOUNT fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style PG_START fill:#ffb86c,stroke:#6272a4,color:#282a36
    style READY fill:#50fa7b,stroke:#6272a4,color:#282a36
    style E1 fill:#ff79c6,stroke:#6272a4,color:#282a36
    style E2 fill:#ff79c6,stroke:#6272a4,color:#282a36
    style E3 fill:#ff79c6,stroke:#6272a4,color:#282a36
    style E4 fill:#ff79c6,stroke:#6272a4,color:#282a36
```

---

## Step 5: DNS Records Created by Headless Service

```mermaid
graph LR
    subgraph HS["🔍 Headless Service: postgres"]
        DNS[DNS Records Created]
    end
    
    DNS --> R0["postgres-0.postgres.default.svc.cluster.local"]
    DNS --> R1["postgres-1.postgres.default.svc.cluster.local"]
    DNS --> R2["postgres-2.postgres.default.svc.cluster.local"]
    
    R0 --> IP0[Pod IP: 10.244.0.10]
    R1 --> IP1[Pod IP: 10.244.0.11]
    R2 --> IP2[Pod IP: 10.244.0.12]
    
    style DNS fill:#8be9fd,stroke:#6272a4,color:#282a36
    style R0 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style R1 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style R2 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style IP0 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style IP1 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style IP2 fill:#8be9fd,stroke:#6272a4,color:#282a36
```

---

## Step 6: Client Connection Flow

```mermaid
flowchart TD
    CLIENT[👤 Client Application]
    
    subgraph OPT1["🟢 Option 1: Load Balanced"]
        LB[Service: postgres-lb<br/>ClusterIP: 10.96.100.50]
    end
    
    subgraph OPT2["🔵 Option 2: Direct Pod Access"]
        HEADLESS[Headless Service]
        DNS0[postgres-0.postgres...]
        DNS1[postgres-1.postgres...]
    end
    
    CLIENT -->|"Connect to postgres-lb:5432"| LB
    LB -->|Round Robin| POD0[postgres-0]
    LB -->|Round Robin| POD1[postgres-1]
    LB -->|Round Robin| POD2[postgres-2]
    
    CLIENT -->|"Connect to postgres-0.postgres:5432"| DNS0
    DNS0 --> POD0
    CLIENT -->|"Connect to postgres-1.postgres:5432"| DNS1
    DNS1 --> POD1
    
    style CLIENT fill:#8be9fd,stroke:#6272a4,color:#282a36
    style LB fill:#ffb86c,stroke:#6272a4,color:#282a36
    style HEADLESS fill:#bd93f9,stroke:#6272a4,color:#282a36
    style DNS0 fill:#bd93f9,stroke:#6272a4,color:#282a36
    style DNS1 fill:#bd93f9,stroke:#6272a4,color:#282a36
    style POD0 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style POD1 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style POD2 fill:#8be9fd,stroke:#6272a4,color:#282a36
```

---

## What Happens When a Pod Crashes?

```mermaid
sequenceDiagram
    participant STS as StatefulSet Controller
    participant Node as Worker Node
    participant PVC as Existing PVC
    
    Note over Node: postgres-0 crashes!
    Node-->>STS: Pod postgres-0 terminated
    
    Note over STS: Current: 2 pods<br/>Desired: 3 pods
    
    STS->>Node: Create Pod: postgres-0 (same name!)
    Note over STS: Uses existing PVC
    STS->>PVC: Attach PVC: postgres-storage-postgres-0
    PVC-->>STS: Already exists, reattach
    
    Node-->>STS: Pod Running
    Node-->>STS: Pod Ready ✓
    
    Note over Node: Data preserved!<br/>Same hostname, same storage
```

---

## Scaling Up (replicas: 3 → 5)

```bash
kubectl scale statefulset postgres --replicas=5
```

```mermaid
flowchart LR
    subgraph BEFORE["⬅️ Before: 3 Replicas"]
        P0[postgres-0]
        P1[postgres-1]
        P2[postgres-2]
    end
    
    SCALE[➡️ Scale to 5]
    
    subgraph AFTER["✅ After: 5 Replicas"]
        P0_2[postgres-0]
        P1_2[postgres-1]
        P2_2[postgres-2]
        P3[postgres-3 NEW]
        P4[postgres-4 NEW]
    end
    
    P0 --> SCALE --> P0_2
    P1 --> SCALE --> P1_2
    P2 --> SCALE --> P2_2
    SCALE --> P3
    SCALE --> P4
    
    Note1[Created in order:<br/>postgres-3 first<br/>then postgres-4]
    
    style P0 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style P1 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style P2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style SCALE fill:#ffb86c,stroke:#6272a4,color:#282a36
    style P0_2 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style P1_2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style P2_2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style P3 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style P4 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style Note1 fill:#bd93f9,stroke:#6272a4,color:#282a36
```

---

## Scaling Down (replicas: 5 → 2)

```bash
kubectl scale statefulset postgres --replicas=2
```

```mermaid
flowchart LR
    subgraph BEFORE["⬅️ Before: 5 Replicas"]
        P0[postgres-0]
        P1[postgres-1]
        P2[postgres-2]
        P3[postgres-3]
        P4[postgres-4]
    end
    
    SCALE[➡️ Scale to 2]
    
    subgraph AFTER["✅ After: 2 Replicas"]
        P0_2[postgres-0]
        P1_2[postgres-1]
    end
    
    P0 --> SCALE --> P0_2
    P1 --> SCALE --> P1_2
    P2 --> SCALE --> DELETED
    P3 --> SCALE --> DELETED
    P4 --> SCALE --> DELETED
    
    DELETED[❌ Deleted in reverse:<br/>postgres-4 first<br/>then postgres-3<br/>then postgres-2]
    
    Note2[⚠️ PVCs NOT deleted!<br/>Data preserved for scale-up]
    
    style P0 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style P1 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style P2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style P3 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style P4 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style SCALE fill:#ffb86c,stroke:#6272a4,color:#282a36
    style P0_2 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style P1_2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style DELETED fill:#ff5555,stroke:#6272a4,color:#282a36
    style Note2 fill:#f1fa8c,stroke:#6272a4,color:#282a36
```

---

## Rolling Update Flow

```bash
kubectl set image statefulset/postgres postgres=postgres:14
```

```mermaid
sequenceDiagram
    participant STS as StatefulSet Controller
    participant P2 as postgres-2
    participant P1 as postgres-1
    participant P0 as postgres-0
    
    Note over STS: Update Strategy: RollingUpdate<br/>Updates in REVERSE order
    
    STS->>P2: Terminate postgres-2
    P2-->>STS: Terminated
    STS->>P2: Create postgres-2 with new image
    P2-->>STS: Ready ✓
    
    STS->>P1: Terminate postgres-1
    P1-->>STS: Terminated
    STS->>P1: Create postgres-1 with new image
    P1-->>STS: Ready ✓
    
    STS->>P0: Terminate postgres-0
    P0-->>STS: Terminated
    STS->>P0: Create postgres-0 with new image
    P0-->>STS: Ready ✓
    
    Note over STS: All pods updated!
```

---

## Cleanup: What Gets Deleted

```bash
kubectl delete -f statefulset-postgresql.yaml
```

```mermaid
graph TD
    DELETE[🗑️ kubectl delete -f statefulset-postgresql.yaml]
    
    DELETE -->|"✓ Deleted"| SVC1[Service: postgres]
    DELETE -->|"✓ Deleted"| SVC2[Service: postgres-lb]
    DELETE -->|"✓ Deleted"| CM[ConfigMap: postgres-config]
    DELETE -->|"✓ Deleted"| SEC[Secret: postgres-secret]
    DELETE -->|"✓ Deleted"| STS[StatefulSet: postgres]
    DELETE -->|"✓ Deleted"| PODS[All Pods]
    
    DELETE -.->|"❌ NOT Deleted!"| PVC0[PVC: postgres-storage-postgres-0]
    DELETE -.->|"❌ NOT Deleted!"| PVC1[PVC: postgres-storage-postgres-1]
    DELETE -.->|"❌ NOT Deleted!"| PVC2[PVC: postgres-storage-postgres-2]
    
    NOTE[⚠️ PVCs must be deleted manually:<br/>kubectl delete pvc -l app=postgres]
    
    style DELETE fill:#ff5555,stroke:#6272a4,color:#282a36
    style SVC1 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style SVC2 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style CM fill:#50fa7b,stroke:#6272a4,color:#282a36
    style SEC fill:#50fa7b,stroke:#6272a4,color:#282a36
    style STS fill:#50fa7b,stroke:#6272a4,color:#282a36
    style PODS fill:#50fa7b,stroke:#6272a4,color:#282a36
    style PVC0 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style PVC1 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style PVC2 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style NOTE fill:#ffb86c,stroke:#6272a4,color:#282a36
```

---

## Complete Architecture Summary

```mermaid
graph TB
    subgraph External["🌐 External"]
        CLIENT[👤 Client Application]
    end
    
    subgraph Cluster["☸️ Kubernetes Cluster"]
        subgraph Services["🔗 Services"]
            LB[📡 postgres-lb<br/>ClusterIP: 10.96.x.x]
            HEADLESS[🔍 postgres<br/>ClusterIP: None]
        end
        
        subgraph Config["⚙️ Configuration"]
            CM[📋 ConfigMap<br/>postgres-config]
            SEC[🔐 Secret<br/>postgres-secret]
        end
        
        subgraph STS["🗃️ StatefulSet: postgres"]
            POD0[🟢 postgres-0<br/>Primary]
            POD1[🔵 postgres-1<br/>Replica]
            POD2[🔵 postgres-2<br/>Replica]
        end
        
        subgraph Storage["💾 Persistent Storage"]
            PVC0[📦 PVC-0<br/>2Gi]
            PVC1[📦 PVC-1<br/>2Gi]
            PVC2[📦 PVC-2<br/>2Gi]
        end
    end
    
    %% Client Traffic (Orange lines)
    CLIENT --> LB
    LB --> POD0
    LB --> POD1
    LB --> POD2
    
    %% DNS Resolution (Blue dashed lines)
    HEADLESS -.->|DNS| POD0
    HEADLESS -.->|DNS| POD1
    HEADLESS -.->|DNS| POD2
    
    %% ConfigMap injection (Purple lines)
    CM --> POD0
    CM --> POD1
    CM --> POD2
    
    %% Secret injection (Red lines)
    SEC --> POD0
    SEC --> POD1
    SEC --> POD2
    
    %% Storage mounting (Yellow lines)
    POD0 --> PVC0
    POD1 --> PVC1
    POD2 --> PVC2

    %% Node Styling
    style CLIENT fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#01579b
    style LB fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#e65100
    style HEADLESS fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#e65100
    style CM fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#7b1fa2
    style SEC fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#c2185b
    style POD0 fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#1b5e20
    style POD1 fill:#bbdefb,stroke:#1565c0,stroke-width:2px,color:#0d47a1
    style POD2 fill:#bbdefb,stroke:#1565c0,stroke-width:2px,color:#0d47a1
    style PVC0 fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#f57f17
    style PVC1 fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#f57f17
    style PVC2 fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#f57f17

    %% Link Styling (Colored Lines)
    %% Client to LB (Orange - Traffic)
    linkStyle 0 stroke:#e65100,stroke-width:3px
    %% LB to Pods (Orange - Traffic)
    linkStyle 1 stroke:#e65100,stroke-width:2px
    linkStyle 2 stroke:#e65100,stroke-width:2px
    linkStyle 3 stroke:#e65100,stroke-width:2px
    %% Headless DNS (Blue - DNS Resolution)
    linkStyle 4 stroke:#1565c0,stroke-width:2px,stroke-dasharray:5
    linkStyle 5 stroke:#1565c0,stroke-width:2px,stroke-dasharray:5
    linkStyle 6 stroke:#1565c0,stroke-width:2px,stroke-dasharray:5
    %% ConfigMap (Purple - Config Injection)
    linkStyle 7 stroke:#7b1fa2,stroke-width:2px
    linkStyle 8 stroke:#7b1fa2,stroke-width:2px
    linkStyle 9 stroke:#7b1fa2,stroke-width:2px
    %% Secret (Red/Pink - Secret Injection)
    linkStyle 10 stroke:#c2185b,stroke-width:2px
    linkStyle 11 stroke:#c2185b,stroke-width:2px
    linkStyle 12 stroke:#c2185b,stroke-width:2px
    %% PVC (Yellow - Storage)
    linkStyle 13 stroke:#f9a825,stroke-width:3px
    linkStyle 14 stroke:#f9a825,stroke-width:3px
    linkStyle 15 stroke:#f9a825,stroke-width:3px
```

### Color Legend

| Line Color | Connection Type | Description |
|------------|-----------------|-------------|
| 🟧 **Orange** | Client Traffic | Client → Service → Pods (network requests) |
| 🔵 **Blue Dashed** | DNS Resolution | Headless Service → Pods (DNS lookup) |
| 🟪 **Purple** | ConfigMap | Config injection into pods (env vars) |
| 🟥 **Pink/Red** | Secret | Secret injection into pods (passwords) |
| 🟨 **Yellow** | Storage | Pods → PVCs (persistent data mount) |

### Node Color Legend

| Color | Component Type | Description |
|-------|---------------|-------------|
| 🟦 Light Blue | Client | External application connecting to cluster |
| 🟧 Orange | Services | Network endpoints (LoadBalancer & Headless) |
| 🟪 Purple | ConfigMap | Non-sensitive configuration data |
| 🟥 Pink | Secret | Sensitive data (passwords) |
| 🟩 Green | Primary Pod | First pod (postgres-0), typically the leader |
| 🔵 Blue | Replica Pods | Secondary pods (postgres-1, postgres-2) |
| 🟨 Yellow | PVCs | Persistent storage volumes |

---

## How Client Connection Works (Step-by-Step)

When a client application wants to connect to PostgreSQL, here's exactly what happens:

```mermaid
sequenceDiagram
    participant Client as 👤 Client App
    participant DNS as 🌐 Cluster DNS
    participant SVC as 📡 postgres-lb Service
    participant IPTABLES as 🔀 kube-proxy/iptables
    participant POD as 🟢 postgres-0/1/2

    Note over Client: Client wants to connect to database
    
    Note over Client,DNS: 🟠 Step 1: DNS Resolution
    Client->>DNS: Resolve "postgres-lb.default.svc.cluster.local"
    DNS-->>Client: Returns ClusterIP: 10.96.100.50
    
    Note over Client,SVC: 🔵 Step 2: Connect to Service IP
    Client->>SVC: TCP Connect to 10.96.100.50:5432
    
    Note over SVC,IPTABLES: 🟢 Step 3: Load Balancing
    SVC->>IPTABLES: Service receives packet
    Note over IPTABLES: kube-proxy rules select<br/>random healthy pod endpoint
    IPTABLES->>POD: Forward to postgres-1:5432<br/>(example: selected randomly)
    
    Note over POD: 🟣 Step 4: Database Processing
    POD->>POD: PostgreSQL processes query
    
    Note over POD,Client: 💗 Step 5: Response
    POD-->>Client: Return query results
```

### Connection Flow Breakdown

```mermaid
flowchart LR
    subgraph Step1["🟠 Step 1: DNS Lookup"]
        C1[Client] -->|"postgres-lb?"| DNS1[CoreDNS]
        DNS1 -->|"10.96.100.50"| C1
    end
    
    subgraph Step2["🔵 Step 2: Service Routing"]
        C2[Client] -->|":5432"| SVC2[ClusterIP<br/>10.96.100.50]
    end
    
    subgraph Step3["🟢 Step 3: Pod Selection"]
        SVC3[Service] -->|"iptables NAT"| LB3{Load<br/>Balancer}
        LB3 -->|"33%"| P0[postgres-0]
        LB3 -->|"33%"| P1[postgres-1]
        LB3 -->|"33%"| P2[postgres-2]
    end
    
    subgraph Step4["🟡 Step 4: Data Access"]
        POD4[Selected Pod] -->|"Read/Write"| PVC4[PVC Storage]
    end
    
    style C1 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style C2 fill:#8be9fd,stroke:#6272a4,color:#282a36
    style DNS1 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style SVC2 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style SVC3 fill:#ffb86c,stroke:#6272a4,color:#282a36
    style LB3 fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style P0 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style P1 fill:#bd93f9,stroke:#6272a4,color:#282a36
    style P2 fill:#bd93f9,stroke:#6272a4,color:#282a36
    style POD4 fill:#50fa7b,stroke:#6272a4,color:#282a36
    style PVC4 fill:#f1fa8c,stroke:#6272a4,color:#282a36
```

### Two Ways to Connect

| Method | Service | Use Case | Example Connection String |
|--------|---------|----------|---------------------------|
| **Load Balanced** | `postgres-lb` | General client apps | `postgresql://admin:pass@postgres-lb:5432/mydb` |
| **Direct Pod** | `postgres` (headless) | Replication, specific pod access | `postgresql://admin:pass@postgres-0.postgres:5432/mydb` |

### Direct Pod Access (via Headless Service)

```mermaid
sequenceDiagram
    participant Client as 👤 Client App
    participant DNS as 🌐 Cluster DNS
    participant POD0 as 🟢 postgres-0

    Note over Client: Client needs to connect to PRIMARY specifically
    
    Note over Client,DNS: 🟠 Step 1: DNS Resolution (Headless)
    Client->>DNS: Resolve "postgres-0.postgres.default.svc.cluster.local"
    DNS-->>Client: Returns Pod IP: 10.244.0.15 (direct!)
    
    Note over Client,POD0: 🟢 Step 2: Direct Connection
    Client->>POD0: TCP Connect directly to 10.244.0.15:5432
    Note over POD0: No load balancing!<br/>Always reaches postgres-0
    
    Note over POD0,Client: 🟣 Step 3: Response
    POD0-->>Client: Return results
```

### When to Use Each Connection Method

```mermaid
flowchart TD
    START{What's your<br/>use case?}
    
    START -->|"General read/write"| LB[🟢 Use postgres-lb<br/>Load Balanced]
    START -->|"Need specific pod"| DIRECT[🔵 Use postgres headless<br/>Direct Access]
    START -->|"Database replication"| DIRECT
    START -->|"Write to primary only"| PRIMARY[🟢 Connect to<br/>postgres-0.postgres]
    START -->|"Read from replicas"| REPLICA[🔵 Connect to<br/>postgres-1.postgres<br/>or postgres-2.postgres]
    
    LB --> LB_EX["postgresql://admin:pass@<br/>postgres-lb:5432/mydb"]
    PRIMARY --> PRIMARY_EX["postgresql://admin:pass@<br/>postgres-0.postgres:5432/mydb"]
    REPLICA --> REPLICA_EX["postgresql://admin:pass@<br/>postgres-1.postgres:5432/mydb"]
    
    style START fill:#ffb86c,stroke:#6272a4,color:#282a36
    style LB fill:#50fa7b,stroke:#6272a4,color:#282a36
    style DIRECT fill:#8be9fd,stroke:#6272a4,color:#282a36
    style PRIMARY fill:#50fa7b,stroke:#6272a4,color:#282a36
    style REPLICA fill:#bd93f9,stroke:#6272a4,color:#282a36
    style LB_EX fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style PRIMARY_EX fill:#f1fa8c,stroke:#6272a4,color:#282a36
    style REPLICA_EX fill:#f1fa8c,stroke:#6272a4,color:#282a36
```

---

## Quick Reference Commands

| Action | Command |
|--------|---------|
| Deploy | `kubectl apply -f statefulset-postgresql.yaml` |
| Watch pods | `kubectl get pods -w -l app=postgres` |
| Check StatefulSet | `kubectl get statefulset postgres` |
| Check PVCs | `kubectl get pvc` |
| Connect to DB | `kubectl exec -it postgres-0 -- psql -U admin -d mydb` |
| Scale up | `kubectl scale statefulset postgres --replicas=5` |
| Scale down | `kubectl scale statefulset postgres --replicas=2` |
| Update image | `kubectl set image statefulset/postgres postgres=postgres:14` |
| Delete all | `kubectl delete -f statefulset-postgresql.yaml` |
| Delete PVCs | `kubectl delete pvc -l app=postgres` |
