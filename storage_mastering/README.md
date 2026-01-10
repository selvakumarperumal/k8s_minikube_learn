# Kubernetes Storage Mastery Guide

> **Complete guide to mastering Kubernetes storage with Minikube**

---

## 📚 Guide Structure

| Chapter | File | Topic |
|---------|------|-------|
| 1 | [01-volumes-basics.md](01-volumes-basics.md) | Volumes & Volume Types |
| 2 | [02-persistentvolumes.md](02-persistentvolumes.md) | PV & PVC |
| 3 | [03-storageclasses.md](03-storageclasses.md) | Dynamic Provisioning |
| 4 | [04-csi-drivers.md](04-csi-drivers.md) | CSI & Cloud Storage |

### Examples Folder
| File | Examples |
|------|----------|
| [examples/01-volumes-examples.yaml](examples/01-volumes-examples.yaml) | emptyDir, hostPath, configMap, secret |
| [examples/02-pv-pvc-examples.yaml](examples/02-pv-pvc-examples.yaml) | Static PV, PVC, access modes |
| [examples/03-storageclass-examples.yaml](examples/03-storageclass-examples.yaml) | Dynamic provisioning |
| [examples/04-statefulset-storage.yaml](examples/04-statefulset-storage.yaml) | StatefulSet with storage |

---

## Storage Overview

```mermaid
flowchart TB
    subgraph Pod["Pod"]
        Container["Container"] --> VolMount["Volume Mount"]
    end
    
    subgraph Storage["Storage Abstraction"]
        VolMount --> Volume["Volume"]
        Volume --> PVC["PersistentVolumeClaim"]
        PVC --> PV["PersistentVolume"]
    end
    
    subgraph Backend["Storage Backend"]
        PV --> Disk["Physical Storage<br/>(Disk, NFS, Cloud)"]
    end
    
    SC["StorageClass"] -.->|"Dynamic Provisioning"| PV
    
    style PVC fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style PV fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style SC fill:#ffb86c,stroke:#f1fa8c,color:#282a36
```

---

## Quick Start

```bash
# Minikube has a default StorageClass
minikube start

# Check default StorageClass
kubectl get storageclass

# View storage examples
kubectl apply -f examples/01-volumes-examples.yaml
```

---

## Learning Path

```mermaid
flowchart LR
    V["1. Volumes<br/>(emptyDir, hostPath)"] --> PV["2. PV & PVC<br/>(Static Provisioning)"]
    PV --> SC["3. StorageClass<br/>(Dynamic Provisioning)"]
    SC --> CSI["4. CSI Drivers<br/>(Cloud Storage)"]
    
    style V fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style PV fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style SC fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style CSI fill:#8be9fd,stroke:#50fa7b,color:#282a36
```

---

## Key Concepts at a Glance

| Concept | Description | Persistence |
|---------|-------------|-------------|
| **emptyDir** | Temporary storage, deleted with pod | ❌ Pod lifecycle |
| **hostPath** | Node's filesystem | ⚠️ Node-bound |
| **PersistentVolume** | Cluster-wide storage resource | ✅ Independent |
| **PersistentVolumeClaim** | Request for storage | ✅ Independent |
| **StorageClass** | Template for dynamic PV creation | N/A |
| **CSI Driver** | Plugin for external storage | ✅ External |

---

## Next: [Chapter 1 - Volumes Basics →](01-volumes-basics.md)
