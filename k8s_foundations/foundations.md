# Kubernetes Foundations - Complete Hands-On Lab with Explanations

## Prerequisites Setup

```bash
# Install Minikube (if not installed)
# For Linux:
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start Minikube with Docker driver
# EXPLANATION: Minikube creates a single-node Kubernetes cluster on your local machine.
# The --driver=docker flag tells Minikube to run the cluster inside a Docker container.
# This is easier than using a VM and works on most systems.
minikube start --driver=docker

# Verify installation
kubectl version --client
minikube status
```

**🔍 What Just Happened?**
- Minikube created a Docker container running a complete Kubernetes cluster
- This single-node cluster includes all K8s components: API server, etcd, scheduler, controller-manager, kubelet
- kubectl is now configured to talk to this Minikube cluster
- **Note**: Minikube is a single-node cluster for local development - in production, you'd have multiple nodes

---

## Part 1: Containers & OCI - Docker Basics

**📚 OCI (Open Container Initiative) Concepts:**
- **OCI**: Standards for container formats and runtimes (Docker implements these)
- **Container**: An isolated process with its own filesystem, network, and resources
- **Image**: A read-only template containing everything needed to run a container

### 1.1 Create FastAPI Application

**app.py**
```python
from fastapi import FastAPI
import os
import socket

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "Hello from Kubernetes!",
        "hostname": socket.gethostname(),  # Shows which pod/container this is
        "version": os.getenv("APP_VERSION", "1.0")  # Read from environment
    }

@app.get("/health")
def health_check():
    return {"status": "healthy"}  # Used by K8s to check if app is alive
```

**requirements.txt**
```
fastapi==0.104.1
uvicorn==0.24.0
```

**Dockerfile**
```dockerfile
# BASE IMAGE: Starting point with Python already installed
FROM python:3.11-slim

# Set working directory inside the container
WORKDIR /app

# LAYER 1: Copy and install dependencies first
# WHY? Docker caches layers. If code changes but deps don't, this layer is reused
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# LAYER 2: Copy application code
# This changes more frequently, so it's a separate layer
COPY app.py .

# Document which port the app uses (doesn't actually publish it)
EXPOSE 8000

# Command to run when container starts
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

**🔍 Why This Structure?**
- **Layer caching**: Dependency installation is slow. By copying requirements.txt first, Docker caches this layer and only rebuilds if requirements change
- **Slim image**: `python:3.11-slim` is smaller than `python:3.11` (165MB vs 1GB)
- **Non-root**: In production, you'd add a USER directive for security

### 1.2 Understanding Docker Layers

```bash
# Build the image
# EXPLANATION: Docker executes each Dockerfile instruction as a separate layer
# Each layer is an immutable snapshot of the filesystem changes
docker build -t fastapi-app:v1 .

# Inspect layers
# Shows each layer's size and the command that created it
docker history fastapi-app:v1

# Check image size
docker images fastapi-app:v1

# Inspect image details (full JSON metadata)
docker inspect fastapi-app:v1

# View layer information
# RootFS shows the actual layer IDs (SHA256 hashes)
docker inspect fastapi-app:v1 | grep -A 20 "RootFS"
```

**🔍 Understanding the Output:**

When you run `docker history fastapi-app:v1`, you'll see:
```
IMAGE          CREATED          CREATED BY                                      SIZE
<sha256>       2 minutes ago    CMD ["uvicorn" "app:app" "--host" "0.0.0.0"…   0B
<sha256>       2 minutes ago    EXPOSE 8000                                     0B
<sha256>       2 minutes ago    COPY app.py .                                   500B
<sha256>       2 minutes ago    RUN pip install --no-cache-dir -r requireme…    15MB
<sha256>       2 minutes ago    COPY requirements.txt .                         50B
<sha256>       2 minutes ago    WORKDIR /app                                    0B
<sha256>       3 weeks ago      /bin/sh -c #(nop)  CMD ["python3"]              0B
...                             [base python:3.11-slim layers]                  165MB
```

**Key Insights:**
- **Most layers are 0B**: Metadata-only layers (CMD, EXPOSE, WORKDIR) don't add size
- **Big layer**: `RUN pip install` adds 15MB (all Python dependencies)
- **Layer reuse**: If you rebuild without changing requirements.txt, Docker skips the pip install layer
- **Base image**: python:3.11-slim contributes ~165MB

**💡 Layer Optimization Tips:**
- Put frequently-changing code (app.py) in later layers
- Combine multiple RUN commands with && to reduce layers
- Use .dockerignore to exclude unnecessary files

### 1.3 Working with Registries

**📚 Container Registry Concepts:**
- **Registry**: A service that stores and distributes container images (like GitHub for images)
- **Repository**: A collection of related images (e.g., fastapi-app)
- **Tag**: A version identifier (e.g., v1, latest, 2.0.1)
- **Full image name format**: `registry/repository:tag` (e.g., `docker.io/library/python:3.11-slim`)

```bash
# Tag image for local registry
# EXPLANATION: Tags are like Git tags - they're aliases for specific image SHAs
# Format: registry-url/image-name:version
docker tag fastapi-app:v1 localhost:5000/fastapi-app:v1

# Run local registry (optional - skip if using Minikube directly)
# This creates a private registry on your machine
docker run -d -p 5000:5000 --name registry registry:2

# Push to local registry
# EXPLANATION: This uploads the image layers to the registry
# Only layers that don't exist in the registry are uploaded (saves bandwidth)
docker push localhost:5000/fastapi-app:v1

# For Minikube, load image directly (RECOMMENDED APPROACH)
# EXPLANATION: Minikube has its own Docker daemon separate from your host
# This command copies the image from your host Docker into Minikube's Docker
# WHY? Kubernetes inside Minikube can't access images on your host Docker
minikube image load fastapi-app:v1

# Verify image in Minikube
minikube image ls | grep fastapi
```

**🔍 What's Really Happening?**

1. **Your Host Machine** runs Docker Desktop/Docker Engine
2. **Minikube Container** runs its own Docker daemon
3. These are **separate Docker environments**

```
┌─────────────────────────────────────────┐
│  Your Host Machine                      │
│                                         │
│  ┌──────────────────┐                  │
│  │  Host Docker     │                  │
│  │  ┌────────────┐  │   minikube       │
│  │  │ fastapi:v1 │──┼──image load────► │
│  │  └────────────┘  │                  │
│  └──────────────────┘                  │
│                                         │
│         ┌───────────────────────────┐   │
│         │  Minikube Container       │   │
│         │  ┌─────────────────────┐  │   │
│         │  │  Minikube Docker    │  │   │
│         │  │  ┌────────────┐     │  │   │
│         │  │  │ fastapi:v1 │     │  │   │
│         │  │  └────────────┘     │  │   │
│         │  │  ◄── K8s pulls from │  │   │
│         │  │      here           │  │   │
│         │  └─────────────────────┘  │   │
│         └───────────────────────────┘   │
└─────────────────────────────────────────┘
```

**⚠️ Common Mistake:**
Building an image on your host and expecting Kubernetes in Minikube to find it WITHOUT `minikube image load`. It won't work because they're separate Docker environments!

### 1.4 Container Runtime Exploration

**📚 Container Runtime Concepts:**
- **Container Runtime**: Software that actually runs containers (Docker, containerd, CRI-O)
- **Container**: A running instance of an image
- **Process Isolation**: Each container thinks it's alone on the system

```bash
# Run container locally to test
# -d = detached (runs in background)
# -p 8000:8000 = map host port 8000 to container port 8000
# --name = give the container a friendly name
docker run -d -p 8000:8000 --name test-app fastapi-app:v1

# Test the app
curl http://localhost:8000
# Returns: {"message":"Hello from Kubernetes!","hostname":"abc123","version":"1.0"}

curl http://localhost:8000/health
# Returns: {"status":"healthy"}

# Inspect running container
# Shows: network settings, mounts, environment variables, resource limits
docker inspect test-app

# View container processes
# This shows processes INSIDE the container (from container's perspective)
docker top test-app
# You'll see: uvicorn and python processes

# Check logs (stdout/stderr from container)
docker logs test-app
# You'll see: INFO: Started server process, INFO: Uvicorn running on...

# Follow logs in real-time
docker logs -f test-app

# Stop and remove
docker stop test-app && docker rm test-app
```

**🔍 Deep Dive - What's Really Happening:**

When you run `docker run`:

1. **Image → Container**
   - Docker creates a writable layer on top of the read-only image layers
   - This writable layer stores all changes made during container execution
   - When container stops, this layer persists (unless you remove the container)

2. **Namespace Isolation**
   - **PID namespace**: Container sees its own process tree (uvicorn is PID 1)
   - **Network namespace**: Container has its own network stack
   - **Mount namespace**: Container has its own filesystem view
   - **UTS namespace**: Container has its own hostname

3. **Port Mapping (-p 8000:8000)**
   ```
   Your Host                Container
   ┌───────────┐           ┌───────────┐
   │ Port 8000 │───NAT────►│ Port 8000 │
   │           │           │  uvicorn  │
   └───────────┘           └───────────┘
   ```
   Docker uses iptables (NAT rules) to forward traffic

4. **Resource Limits (cgroups)**
   ```bash
   # You can limit resources:
   docker run --memory="128m" --cpus="0.5" fastapi-app:v1
   ```
   cgroups enforce these limits at the kernel level

**💡 Try This Experiment:**

```bash
# Run container
docker run -d --name test fastapi-app:v1

# Exec into container
docker exec -it test /bin/bash

# Inside container, check processes
ps aux  # You'll only see container processes, not host processes

# Check hostname
hostname  # Random ID like "7f8a9b2c3d4e"

# Check network
ip addr  # Container has its own IP (usually 172.17.0.x)

# Exit
exit
```

This demonstrates namespace isolation!

---

## Part 2: Linux & Networking Basics

**📚 Key Linux Concepts for Containers:**
- **Namespaces**: Isolate what a process can SEE (filesystem, network, processes)
- **cgroups (Control Groups)**: Limit what a process can USE (CPU, memory, I/O)
- **iptables**: Firewall rules and network address translation (NAT)
- **DNS**: Domain Name System - translates names to IP addresses

### 2.1 Understanding Namespaces & cgroups

**🎯 What Are Namespaces?**

Think of namespaces like separate rooms in a house. Processes in different rooms can't see each other, even though they're in the same building (Linux kernel).

**Types of Namespaces:**
- **PID**: Process isolation (each container thinks it has its own process tree)
- **NET**: Network isolation (each container has its own network stack)
- **MNT**: Mount points (each container has its own filesystem view)
- **UTS**: Hostname and domain name
- **IPC**: Inter-process communication
- **USER**: User and group IDs

```bash
# SSH into Minikube to explore the actual Linux host running containers
minikube ssh

# List namespaces used by containers
# EXPLANATION: Each row is a namespace. Multiple processes can share a namespace.
sudo lsns

# Example output:
#         NS TYPE   NPROCS   PID USER    COMMAND
# 4026531835 cgroup    100     1 root    /sbin/init
# 4026531836 pid       100     1 root    /sbin/init
# 4026533123 net         5  1234 root    /pause  <-- Pod's network namespace
# 4026533124 pid         2  1235 root    uvicorn <-- Container's PID namespace

# View cgroup for a process
# EXPLANATION: cgroups organize processes into hierarchies and apply resource limits
sudo cat /proc/1/cgroup
# Shows: 0::/init.scope (systemd cgroup hierarchy)

# View network namespaces
# Each pod in Kubernetes gets its own network namespace
sudo ip netns list

# Exit Minikube
exit
```

**🔍 How Containers Use Namespaces:**

```
┌─────────────────────────────────────────────┐
│  Linux Kernel (Minikube Node)               │
│  Note: Minikube = single-node cluster       │
│                                             │
│  ┌──────────────────┐  ┌─────────────────┐ │
│  │ Pod A            │  │ Pod B           │ │
│  │                  │  │                 │ │
│  │ NET Namespace 1  │  │ NET Namespace 2 │ │
│  │ - eth0: 10.0.1.2 │  │ - eth0: 10.0.1.3│ │
│  │                  │  │                 │ │
│  │ ┌──────────────┐ │  │ ┌─────────────┐ │ │
│  │ │Container 1   │ │  │ │Container 3  │ │ │
│  │ │PID Namespace │ │  │ │PID Namespace│ │ │
│  │ └──────────────┘ │  │ └─────────────┘ │ │
│  │ ┌──────────────┐ │  │                 │ │
│  │ │Container 2   │ │  │                 │ │
│  │ │PID Namespace │ │  │                 │ │
│  │ └──────────────┘ │  │                 │ │
│  └──────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────┘
```

**Key Points:**
- Containers in the same pod SHARE a network namespace (can talk via localhost)
- Each container has its own PID namespace (process isolation)
- cgroups ensure one container can't starve others of resources

**🎯 What Are cgroups?**

cgroups are like resource quotas. They limit and monitor what resources a process can consume.

**Example:**
```yaml
# In Kubernetes, you specify:
resources:
  limits:
    memory: "128Mi"  # <-- Enforced by memory cgroup
    cpu: "500m"      # <-- Enforced by CPU cgroup
```

**Behind the scenes:**
- Kernel creates a cgroup for this container
- Memory cgroup kills container if it exceeds 128Mi (OOMKilled)
- CPU cgroup throttles container to 50% of one core

### 2.2 Kubernetes Networking Inspection

**📚 Kubernetes Networking Model:**
- Every pod gets its own IP address
- Pods can communicate with each other without NAT
- Containers within a pod share the network namespace (localhost)

**network-test-pod.yaml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  labels:
    app: network-test
spec:
  containers:
  - name: network-tools
    image: nicolaka/netshoot  # Swiss-army knife for network debugging
    command: ["sleep", "3600"]  # Keep container running for 1 hour
```

```bash
# Deploy network test pod
kubectl apply -f network-test-pod.yaml

# Wait for pod to be ready
# EXPLANATION: Kubernetes needs to pull the image, create the pod, start the container
kubectl wait --for=condition=ready pod/network-test

# Execute commands inside pod
# -it = interactive terminal
# -- bash = command to run (starts bash shell)
kubectl exec -it network-test -- bash

# ==========================================
# Inside the pod, run these commands:
# ==========================================

# View network interfaces
ip addr
# You'll see:
# - lo (loopback): 127.0.0.1 for localhost communication
# - eth0: Pod's IP (e.g., 10.244.0.5) - this is how pod talks to others

# View routing table
ip route
# Shows:
# - default via 10.244.0.1 (gateway to reach other pods/services)
# - 10.244.0.0/24 (pod network CIDR)

# View DNS configuration
cat /etc/resolv.conf
# Shows:
# nameserver 10.96.0.10  <-- CoreDNS service IP
# search default.svc.cluster.local svc.cluster.local cluster.local
# This is why you can use short names like "demo-service" instead of full FQDN

# Test DNS resolution
nslookup kubernetes.default
# EXPLANATION: 'kubernetes' is the API server service
# 'default' is the namespace
# Returns the ClusterIP of the kubernetes service

# View iptables rules (if permissions allow)
iptables -L -n -v
# EXPLANATION: kube-proxy uses iptables to implement services
# You'll see KUBE-SERVICES chain with rules for each service

# Exit pod
exit
```

**🔍 What's Really Happening - Pod Networking:**

```
┌─────────────────────────────────────────────────────────┐
│  Minikube Node (single-node Kubernetes cluster)         │
│                                                          │
│  ┌──────────────────┐      ┌──────────────────┐        │
│  │ Pod: network-test│      │ Pod: app-pod     │        │
│  │ IP: 10.244.0.5   │      │ IP: 10.244.0.6   │        │
│  │                  │      │                  │        │
│  │ ┌──────────────┐ │      │ ┌──────────────┐ │        │
│  │ │ netshoot     │ │      │ │ fastapi      │ │        │
│  │ │ container    │ │      │ │ container    │ │        │
│  │ └──────────────┘ │      │ └──────────────┘ │        │
│  └────────┬─────────┘      └────────┬─────────┘        │
│           │                         │                   │
│           │    ┌────────────────────┤                   │
│           │    │                    │                   │
│      ┌────▼────▼────────────────────▼──────┐           │
│      │   Linux Bridge (cbr0)                │           │
│      │   Network: 10.244.0.0/24             │           │
│      └──────────────┬───────────────────────┘           │
│                     │                                   │
│              ┌──────▼────────┐                          │
│              │  Node's eth0  │                          │
│              │  (External)   │                          │
│              └───────────────┘                          │
└─────────────────────────────────────────────────────────┘

Note: In Minikube, there's only ONE node. In production clusters,
      you'd have multiple nodes, each with its own pod network.
```

**How Pods Communicate:**
1. Pod A (10.244.0.5) wants to talk to Pod B (10.244.0.6)
2. Packet goes from Pod A's eth0 → Linux bridge
3. Bridge routes to Pod B's eth0
4. All without NAT (pods use real IPs)

### 2.3 Service Networking & DNS

**📚 Kubernetes Services:**
- **Problem**: Pod IPs change when pods restart
- **Solution**: Services provide a stable IP and DNS name
- **How**: kube-proxy watches for service changes and updates iptables rules

**service-network-demo.yaml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  labels:
    app: demo  # This label is KEY for service selector
spec:
  containers:
  - name: fastapi
    image: fastapi-app:v1
    imagePullPolicy: Never  # Don't try to pull, use local image
    ports:
    - containerPort: 8000  # App listens on this port
---
apiVersion: v1
kind: Service
metadata:
  name: demo-service  # This becomes the DNS name
spec:
  selector:
    app: demo  # Route traffic to pods with label app=demo
  ports:
  - protocol: TCP
    port: 80         # Service listens on port 80
    targetPort: 8000 # Forward to container port 8000
  type: ClusterIP    # Only accessible within cluster (default)
```

**🔍 Understanding the Service:**
- **selector**: Finds pods with `app: demo` label
- **port**: What clients connect to (80)
- **targetPort**: Where traffic goes in the pod (8000)
- **ClusterIP**: Service gets a virtual IP (e.g., 10.96.0.50)

```bash
# Deploy the service
kubectl apply -f service-network-demo.yaml

# Test DNS resolution from network-test pod
kubectl exec -it network-test -- nslookup demo-service
# Returns:
# Name:    demo-service.default.svc.cluster.local
# Address: 10.96.0.50  <-- Service's ClusterIP (virtual, not real)

kubectl exec -it network-test -- nslookup demo-service.default.svc.cluster.local
# Same result - DNS search domains let you use short names

# Test service connectivity
kubectl exec -it network-test -- curl http://demo-service
# This works! Even though demo-service IP is virtual
# Returns: {"message":"Hello from Kubernetes!","hostname":"app-pod",...}

# View service endpoints
# EXPLANATION: Endpoints are the actual pod IPs behind the service
kubectl get endpoints demo-service
# Shows:
# NAME           ENDPOINTS        AGE
# demo-service   10.244.0.6:8000  1m

# Describe service to see networking details
kubectl describe service demo-service
# Shows:
# - ClusterIP (virtual IP)
# - Endpoints (real pod IPs)
# - Port mappings
```

**🔍 How Services Work - The Magic of iptables:**

```
Client Pod (network-test)
    │
    │ curl http://demo-service:80
    │
    ▼
┌───────────────────────────────────────┐
│  iptables (on every node)             │
│                                       │
│  IF destination = 10.96.0.50:80       │  <-- Service ClusterIP
│  THEN DNAT to 10.244.0.6:8000         │  <-- Pod IP
└───────────────────────────────────────┘
    │
    ▼
┌─────────────────────┐
│  Pod: app-pod       │
│  IP: 10.244.0.6     │
│  ┌───────────────┐  │
│  │  FastAPI      │  │
│  │  Port: 8000   │  │
│  └───────────────┘  │
└─────────────────────┘
```

**Step-by-step:**
1. You curl `demo-service:80` (DNS resolves to 10.96.0.50)
2. Packet hits iptables PREROUTING chain
3. kube-proxy has created a rule: "If destination = 10.96.0.50:80, rewrite to 10.244.0.6:8000"
4. Packet is DNAT'd (destination NAT) to the pod
5. Response comes back, DNAT is reversed
6. You see response from the pod!

**💡 DNS in Kubernetes:**

Kubernetes uses CoreDNS to provide service discovery:

```
Service Name:     demo-service
Namespace:        default
Full DNS Name:    demo-service.default.svc.cluster.local

Format: <service-name>.<namespace>.svc.cluster.local
```

**DNS Search Domains (from /etc/resolv.conf):**
```
search default.svc.cluster.local svc.cluster.local cluster.local
```

This means:
- `demo-service` → searches `demo-service.default.svc.cluster.local` ✅
- `demo-service.default` → searches `demo-service.default.svc.cluster.local` ✅
- `demo-service.other-namespace` → works across namespaces ✅

**🎯 Try This Experiment:**

```bash
# Scale up the deployment
kubectl scale deployment fastapi-deployment --replicas=3
# (Assuming you'll create this deployment later)

# Check endpoints - now there are 3!
kubectl get endpoints demo-service
# Shows: 10.244.0.6:8000,10.244.0.7:8000,10.244.0.8:8000

# Make multiple requests
kubectl exec -it network-test -- sh -c 'for i in $(seq 1 10); do curl -s http://demo-service | grep hostname; done'

# You'll see different hostnames - traffic is load balanced!
# {"hostname":"app-pod-abc"}
# {"hostname":"app-pod-def"}
# {"hostname":"app-pod-ghi"}
```

This demonstrates that services automatically load-balance across all matching pods!

### 2.4 Troubleshooting Service Connectivity

**🔧 Common Issue: "Connection Refused" or "Could not connect to server"**

When `curl http://service-name` fails, use these commands to diagnose the problem:

```bash
# ========================================
# STEP 1: Check if pods and services exist
# ========================================

# View all pods and services
kubectl get pods,svc -o wide
# Look for:
# - Pod STATUS: Should be "Running"
# - Pod READY: Should be "1/1" (all containers ready)
# - Service CLUSTER-IP: Should have an IP assigned

# ========================================
# STEP 2: Check if service has endpoints
# ========================================

# View service details
kubectl describe svc <service-name>
# IMPORTANT: Look for "Endpoints" line
# - If empty → Service selector doesn't match any pod labels
# - If has IPs → Service is connected to pods

# List endpoints directly
kubectl get endpoints <service-name>
# Shows the actual pod IPs that will receive traffic

# ========================================
# STEP 3: Verify label matching
# ========================================

# Check pod labels
kubectl get pods --show-labels
# Example: app=demo

# Check service selector
kubectl get svc <service-name> -o yaml | grep -A 2 "selector"
# Must match the pod labels!

# ========================================
# STEP 4: Check the pod is listening on the right port
# ========================================

# View pod logs to see what port the app is using
kubectl logs <pod-name>
# Look for: "Running on http://0.0.0.0:PORT"
# Compare with containerPort and targetPort in YAML

# ========================================
# STEP 5: Test direct pod IP connection
# ========================================

# Get pod IP
kubectl get pod <pod-name> -o wide
# Note the IP column (e.g., 10.244.0.7)

# Test direct connection (bypasses service)
kubectl exec -it <network-test-pod> -- curl http://<pod-ip>:<port>
# If this works but service doesn't → port mismatch in Service definition

# Test service connection
kubectl exec -it <network-test-pod> -- curl http://<service-name>
# If direct works but this fails → DNS or service selector issue
```

**🔍 Real-World Example - Port Mismatch:**

A common mistake is when the app listens on a different port than configured:

```
┌─────────────────────────────────────────────────────────────┐
│  BEFORE (Broken)                                            │
│                                                             │
│  FastAPI app logs: "Server started at http://0.0.0.0:80"   │
│  BUT service.yaml says:                                     │
│    containerPort: 8000  ← WRONG!                           │
│    targetPort: 8000     ← WRONG!                           │
│                                                             │
│  Result: Traffic goes to port 8000 but nothing listens     │
│          → Connection refused!                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  AFTER (Fixed)                                              │
│                                                             │
│  FastAPI app logs: "Server started at http://0.0.0.0:80"   │
│  service.yaml updated to:                                   │
│    containerPort: 80    ← CORRECT!                         │
│    targetPort: 80       ← CORRECT!                         │
│                                                             │
│  Result: Traffic flows correctly → Success!                 │
└─────────────────────────────────────────────────────────────┘
```

**⚠️ Important: Pods cannot be updated in-place for port changes!**

```bash
# If you change containerPort, you must delete and recreate the pod:
kubectl delete pod <pod-name>
kubectl apply -f <pod-yaml>

# Services CAN be updated in-place:
kubectl apply -f <service-yaml>
```

**💡 Quick Troubleshooting Checklist:**

| Check | Command | What to Look For |
|-------|---------|------------------|
| Pod running? | `kubectl get pods` | STATUS=Running, READY=1/1 |
| Service exists? | `kubectl get svc` | ClusterIP assigned |
| Endpoints exist? | `kubectl describe svc <name>` | Endpoints line has IPs |
| Labels match? | `kubectl get pods --show-labels` | Labels match service selector |
| Port correct? | `kubectl logs <pod>` | "Running on" port matches targetPort |
| Direct connection? | `kubectl exec ... curl <pod-ip>:<port>` | Works = app is fine |
| DNS working? | `kubectl exec ... nslookup <svc>` | Returns ClusterIP |

---

## Part 3: Kubernetes Architecture

**📚 Kubernetes Control Plane Components:**

```
┌─────────────────────────────────────────────────────────────┐
│  Control Plane (Brain of Kubernetes)                        │
│  In Minikube: All these run as pods on the single node      │
│                                                              │
│  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │   API Server   │  │ Controller   │  │   Scheduler     │ │
│  │                │  │ Manager      │  │                 │ │
│  │ - REST API     │  │              │  │ - Watches for   │ │
│  │ - Auth         │  │ - Deployment │  │   unscheduled   │ │
│  │ - Validation   │  │   Controller │  │   pods          │ │
│  │ - Admission    │  │ - ReplicaSet │  │ - Finds best    │ │
│  │               │◄──┤   Controller │  │   node          │ │
│  │ All requests   │  │ - Service    │  │   (only 1 in    │ │
│  │ go through     │  │   Controller │  │    Minikube!)   │ │
│  │ here           │  │ - etc.       │  │                 │ │
│  └────────┬───────┘  └──────────────┘  └─────────────────┘ │
│           │                                                  │
│  ┌────────▼───────┐                                         │
│  │     etcd       │  ◄── ALL cluster state stored here     │
│  │                │      (pods, services, configs, etc.)    │
│  │ Key-Value Store│                                         │
│  └────────────────┘                                         │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ kubelet watches API server
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Worker Node (In Minikube, this is the SAME node as above!) │
│                                                              │
│  ┌──────────────┐     ┌──────────────┐                     │
│  │   kubelet    │────►│ Container    │ (Docker/containerd) │
│  │              │     │ Runtime      │                     │
│  │ - Ensures    │     │              │                     │
│  │   pods are   │     └──────────────┘                     │
│  │   running    │                                           │
│  │ - Reports    │     ┌──────────────┐                     │
│  │   status     │     │  kube-proxy  │                     │
│  └──────────────┘     │              │                     │
│                       │ - Manages    │                     │
│                       │   iptables   │                     │
│                       │   for        │                     │
│                       │   services   │                     │
│                       └──────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

**Key Difference: Minikube vs Production:**
- Minikube: 1 node running BOTH control plane AND workloads
- Production: Separate control plane nodes + multiple worker nodes

### 3.1 Exploring Control Plane Components

```bash
# View all system pods
# EXPLANATION: Control plane components run as pods in kube-system namespace
kubectl get pods -n kube-system

# Example output:
# NAME                               READY   STATUS    RESTARTS   AGE
# coredns-5dd5756b68-abc123          1/1     Running   0          10m
# etcd-minikube                      1/1     Running   0          10m
# kube-apiserver-minikube            1/1     Running   0          10m
# kube-controller-manager-minikube   1/1     Running   0          10m
# kube-proxy-xyz789                  1/1     Running   0          10m
# kube-scheduler-minikube            1/1     Running   0          10m
# storage-provisioner                1/1     Running   0          10m

# Check API server
kubectl get pods -n kube-system -l component=kube-apiserver
# This is the ONLY component you interact with via kubectl
# Everything goes through the API server

# Check etcd (the database)
kubectl get pods -n kube-system -l component=etcd

# Check scheduler (decides where pods run)
kubectl get pods -n kube-system -l component=kube-scheduler

# Check controller manager (maintains desired state)
kubectl get pods -n kube-system -l component=kube-controller-manager

# View logs of API server
kubectl logs -n kube-system -l component=kube-apiserver --tail=50
# You'll see: authentication attempts, API requests, etc.

# Check cluster info
kubectl cluster-info
# Shows: Kubernetes control plane URL, CoreDNS URL

# View component statuses (deprecated but still useful)
kubectl get componentstatuses
```

**🔍 What Each Component Does:**

**1. API Server (kube-apiserver)**
- The "front door" of Kubernetes
- All communication goes through it (kubectl, schedulers, controllers, kubelet)
- Validates requests, authenticates users, enforces RBAC
- Only component that talks to etcd directly

**2. etcd**
- Distributed key-value store
- Stores ALL cluster state: pods, services, secrets, config maps, etc.
- Uses Raft consensus algorithm (like multi-leader replication)
- If etcd is down, cluster can't make changes (but pods keep running)

**3. Scheduler (kube-scheduler)**
- Watches for newly created pods with no node assigned
- Evaluates all nodes and picks the best one based on:
  - Resource availability (CPU, memory)
  - Affinity/anti-affinity rules
  - Taints and tolerations
  - Pod resource requests
- Updates pod spec with `nodeName: node-1`

**4. Controller Manager (kube-controller-manager)**
- Runs multiple controllers in a single process:
  - **Deployment Controller**: Manages ReplicaSets for deployments
  - **ReplicaSet Controller**: Ensures correct number of pod replicas
  - **Service Controller**: Creates/updates load balancers for services
  - **Node Controller**: Monitors node health
  - **Job Controller**: Creates pods for jobs
- Each controller watches API server for its resource type
- Reconciliation loop: "Current State → Desired State"

### 3.2 Understanding etcd

**📚 What is etcd?**
- Consistent, distributed key-value store
- The "source of truth" for all cluster state
- Uses Raft consensus algorithm (leader election + log replication)
- Stores data as key-value pairs in a hierarchical structure

**Data Structure in etcd:**
```
/registry/
  ├── pods/
  │   ├── default/
  │   │   └── app-pod  → {pod spec, status, metadata}
  │   └── kube-system/
  │       └── coredns-abc123  → {pod data}
  ├── services/
  │   └── default/
  │       └── demo-service  → {service spec, ClusterIP}
  ├── deployments/
  ├── configmaps/
  └── secrets/  (encrypted!)
```

```bash
# Port-forward to etcd (read-only exploration)
# WARNING: In production, never expose etcd directly!
kubectl port-forward -n kube-system service/etcd 2379:2379 &

# View cluster health (if etcdctl is available)
# Note: In production, direct etcd access is restricted for security

# View all keys stored in etcd via API server
kubectl get --raw /
# Returns: {"paths":["/api","/api/v1","/apis",...]}

# View specific resource in etcd structure
kubectl get --raw /api/v1/namespaces/default/pods
# Returns: JSON list of all pods in default namespace
```

**🔍 How API Server Uses etcd:**

```
1. kubectl create pod my-pod
   │
   ▼
2. API Server
   ├─► Validates YAML schema
   ├─► Authenticates user
   ├─► Authorizes action (RBAC)
   ├─► Runs admission controllers
   └─► Writes to etcd: /registry/pods/default/my-pod
   
3. etcd
   └─► Stores data persistently
   
4. Scheduler watches for pods with no nodeName
   └─► Finds my-pod, schedules it to node-1
   └─► Updates etcd: my-pod.spec.nodeName = "node-1"
   
5. kubelet on node-1 watches for pods assigned to itself
   └─► Sees my-pod, tells container runtime to start it
   └─► Updates etcd: my-pod.status.phase = "Running"
```

**💡 Why etcd is Critical:**
- No etcd = No API server = No kubectl = Cluster frozen
- Pods keep running (kubelet has local cache), but you can't make changes
- Always backup etcd in production!
- **Minikube uses a single etcd instance** - production uses 3 or 5 for high availability (HA)
- In Minikube, if the single node goes down, everything is lost (it's for local dev only!)

### 3.3 Scheduler in Action

**📚 How the Scheduler Works:**

The scheduler's job is to answer: "Which node should this pod run on?"

**Scheduling Process:**
1. **Filtering**: Eliminate nodes that don't meet requirements
   - Not enough CPU/memory
   - Node has taints that pod doesn't tolerate
   - Node selector doesn't match
   - Pod has affinity rules that exclude this node

2. **Scoring**: Rank remaining nodes (0-100 score)
   - Balance resource utilization
   - Spread pods across nodes (for HA)
   - Honor pod affinity/anti-affinity
   - Prefer nodes with fewer pods

3. **Binding**: Update pod's `nodeName` field in etcd

**scheduler-demo.yaml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: scheduler-demo
spec:
  containers:
  - name: app
    image: fastapi-app:v1
    imagePullPolicy: Never
    resources:
      requests:       # "I need at least this much"
        memory: "64Mi"
        cpu: "250m"   # 250 millicores = 0.25 CPU
      limits:         # "Don't let me use more than this"
        memory: "128Mi"
        cpu: "500m"   # 500 millicores = 0.5 CPU
```

**🔍 Understanding Resource Requests & Limits:**

```
┌─────────────────────────────────────────┐
│  Node: minikube (2 CPU, 4GB RAM)       │
│  Note: This is your single Minikube    │
│        node with limited resources     │
│                                         │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Pod A        │  │ Pod B           │ │
│  │ Request:     │  │ Request:        │ │
│  │ - 500m CPU   │  │ - 1000m CPU     │ │
│  │ - 512Mi RAM  │  │ - 1Gi RAM       │ │
│  │              │  │                 │ │
│  │ Limit:       │  │ Limit:          │ │
│  │ - 1000m CPU  │  │ - 2000m CPU     │ │
│  │ - 1Gi RAM    │  │ - 2Gi RAM       │ │
│  └──────────────┘  └─────────────────┘ │
│                                         │
│  Scheduler math:                        │
│  Total requests: 1500m CPU + 1.5Gi RAM │
│  Node has: 2000m CPU + 4Gi RAM         │
│  ✅ Pod C (request 250m CPU) fits!      │
│  ❌ Pod D (request 1000m CPU) won't fit │
│                                         │
│  In Minikube, be careful with          │
│  resource requests - you only have     │
│  ONE node with limited resources!      │
└─────────────────────────────────────────┘
```

**Key Points:**
- **Request**: Scheduler uses this for placement decisions
- **Limit**: cgroup enforces this (CPU throttled, memory OOMKilled)
- **No request = 0** (scheduler thinks pod needs nothing)
- **No limit = unlimited** (pod can use entire node resources!)

```bash
# Deploy pod and watch scheduling
kubectl apply -f scheduler-demo.yaml

# Watch events in real-time
# EXPLANATION: Events show what's happening behind the scenes
kubectl get events --watch &

# You'll see events like:
# - "Scheduled" → Scheduler assigned pod to a node
# - "Pulling" → kubelet is pulling the image
# - "Pulled" → Image pull complete
# - "Created" → Container created
# - "Started" → Container started

# Check which node pod was scheduled on
kubectl get pod scheduler-demo -o wide
# Shows: NODE column tells you which node
# In Minikube, it will always be "minikube" (the single node)
# In production clusters, you'd see different node names like node-1, node-2, etc.

# View scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler --tail=100
# You'll see: Filtering/Scoring logic, final decision

# Kill background watch process
pkill -f "kubectl get events"
```

**🎯 Experiment - Manual Scheduling:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: manual-schedule
spec:
  nodeName: minikube  # Bypass scheduler - force placement
  containers:
  - name: app
    image: fastapi-app:v1
    imagePullPolicy: Never
```

```bash
kubectl apply -f manual-schedule.yaml
# Scheduler is bypassed! Pod goes directly to specified node
# Useful for testing, but risky in production
```

### 3.4 Controllers in Action

**📚 The Controller Pattern:**

Controllers implement the "reconciliation loop":

```
┌───────────────────────────────────────┐
│  Controller Reconciliation Loop       │
│                                       │
│  1. Watch API server for changes     │
│     │                                 │
│     ▼                                 │
│  2. Read current state (from etcd)   │
│     │                                 │
│     ▼                                 │
│  3. Read desired state (from spec)   │
│     │                                 │
│     ▼                                 │
│  4. Calculate diff                   │
│     │                                 │
│     ▼                                 │
│  5. Take action to reconcile         │
│     │                                 │
│     └──────┐                          │
│            ▼                          │
│  6. Wait for next event or timeout   │
│     │                                 │
│     └───► Loop back to step 1        │
└───────────────────────────────────────┘
```

**deployment-controller-demo.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-deployment
spec:
  replicas: 3  # DESIRED STATE: "I want 3 pods"
  selector:
    matchLabels:
      app: fastapi  # Find pods with this label
  template:  # Pod template - used to create new pods
    metadata:
      labels:
        app: fastapi  # Must match selector above
    spec:
      containers:
      - name: fastapi
        image: fastapi-app:v1
        imagePullPolicy: Never
        ports:
        - containerPort: 8000
```

**🔍 What Happens When You Apply This:**

```
You: kubectl apply -f deployment.yaml
│
▼
API Server: Stores deployment in etcd
│
▼
Deployment Controller: "New deployment! I need to create a ReplicaSet"
│
├─► Creates ReplicaSet with replicas=3
│
▼
ReplicaSet Controller: "New ReplicaSet! I need to create 3 pods"
│
├─► Creates Pod 1
├─► Creates Pod 2
└─► Creates Pod 3
│
▼
Scheduler: Assigns each pod to a node
│
▼
kubelet: Starts containers on assigned nodes
│
▼
ReplicaSet Controller: "All 3 pods running, desired state = current state ✓"
```

```bash
# Deploy
kubectl apply -f deployment-controller-demo.yaml

# Watch controller in action
# Open another terminal and run:
kubectl get pods -w &

# You'll see:
# fastapi-deployment-abc123-xyz   0/1     Pending   0          0s
# fastapi-deployment-abc123-xyz   0/1     ContainerCreating   0          0s
# fastapi-deployment-abc123-xyz   1/1     Running   0          2s
# ... (same for other 2 pods)

# Delete a pod and watch it recreate
POD_NAME=$(kubectl get pods -l app=fastapi -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod: $POD_NAME"
kubectl delete pod $POD_NAME

# WATCH WHAT HAPPENS:
# 1. Pod enters "Terminating" state
# 2. ReplicaSet Controller sees: "Current state = 2 pods, desired = 3"
# 3. Controller creates new pod immediately
# 4. New pod goes through: Pending → ContainerCreating → Running
# 5. Current state = desired state again!

# View replicaset (managed by deployment controller)
kubectl get replicasets
# Shows:
# NAME                        DESIRED   CURRENT   READY   AGE
# fastapi-deployment-abc123   3         3         3       5m

# Describe the deployment
kubectl describe deployment fastapi-deployment
# Shows:
# - Replicas: 3 desired | 3 updated | 3 total | 3 available
# - Conditions: Available=True (all replicas are ready)
# - Events: Deployment controller actions

# View controller-manager logs
kubectl logs -n kube-system -l component=kube-controller-manager --tail=100 | grep -i deployment
```

**🎯 The Power of Controllers - Self-Healing:**

```bash
# Scale up
kubectl scale deployment fastapi-deployment --replicas=5
# Deployment Controller updates ReplicaSet
# ReplicaSet Controller creates 2 new pods

# Scale down
kubectl scale deployment fastapi-deployment --replicas=2
# ReplicaSet Controller terminates 3 pods

# Manual interference
kubectl delete pod -l app=fastapi
# Deletes all pods!
# ReplicaSet Controller immediately recreates them
# "Current state = 0, desired = 2, create 2 pods!"

# Kill background watch
pkill -f "kubectl get pods"
```

**🔍 Deployment → ReplicaSet → Pod Hierarchy:**

```
Deployment: fastapi-deployment (replicas=3)
│
└─► ReplicaSet: fastapi-deployment-abc123 (replicas=3)
    │
    ├─► Pod: fastapi-deployment-abc123-xyz
    ├─► Pod: fastapi-deployment-abc123-def
    └─► Pod: fastapi-deployment-abc123-ghi
```

**Why this hierarchy?**
- **Deployment**: Manages updates/rollbacks (creates new ReplicaSets for updates)
- **ReplicaSet**: Ensures pod count (creates/deletes pods)
- **Pod**: Runs containers

**💡 Rolling Update Example:**

```bash
# Update image (simulate new version)
kubectl set image deployment/fastapi-deployment fastapi=fastapi-app:v2

# What happens:
# 1. Deployment Controller creates NEW ReplicaSet (v2)
# 2. Scales new RS up gradually: 0→1→2→3
# 3. Scales old RS down gradually: 3→2→1→0
# 4. Result: Zero downtime update!
```

---

## Part 4: kubectl & YAML Mastery

**📚 kubectl Philosophy:**
- **Declarative**: "I want this state" (kubectl apply)
- **Imperative**: "Do this action" (kubectl create, delete, scale)
- **Kubernetes prefers declarative** - store YAMLs in Git!

### 4.1 CRUD Operations

```bash
# ============================================
# CREATE
# ============================================

# Imperative (quick, but not reproducible)
kubectl create namespace demo-ns
kubectl run nginx --image=nginx

# Declarative (reproducible, GitOps-friendly) - PREFERRED
kubectl apply -f deployment-controller-demo.yaml
# Idempotent: Run it 10 times, same result

# Create from inline YAML
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: inline-ns
EOF

# ============================================
# READ
# ============================================

# List resources
kubectl get deployments
kubectl get pods
kubectl get all  # All resources in current namespace

# Wide output (more columns: IP, node, etc.)
kubectl get pods -o wide

# Full YAML output
kubectl get pod app-pod -o yaml
# Shows: Complete resource definition including status

# JSON output (useful for parsing)
kubectl get pods -o json

# JSONPath (extract specific fields)
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
# Output: pod1 pod2 pod3

# Using jq for JSON parsing
kubectl get pods -o json | jq '.items[].metadata.name'

# Custom columns
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName

# Describe (detailed info + events)
kubectl describe pod app-pod
# Shows: Labels, annotations, status, events, conditions

# Watch for changes
kubectl get pods --watch
# Updates live as pods change state

# ============================================
# UPDATE
# ============================================

# Scale replicas
kubectl scale deployment fastapi-deployment --replicas=5
# Deployment Controller adjusts ReplicaSet

# Update image (rolling update)
kubectl set image deployment/fastapi-deployment fastapi=fastapi-app:v2
# Creates new ReplicaSet, gradually rolls out

# Edit resource directly (opens in editor)
kubectl edit deployment fastapi-deployment
# Changes take effect when you save and exit

# Apply updated YAML
# EXPLANATION: kubectl compares your YAML with what's in etcd
# and calculates the minimal diff to apply
kubectl apply -f deployment-controller-demo.yaml

# Patch (update specific fields)
kubectl patch deployment fastapi-deployment -p '{"spec":{"replicas":10}}'

# Set resources
kubectl set resources deployment fastapi-deployment -c=fastapi --limits=cpu=200m,memory=512Mi

# Annotate (add metadata)
kubectl annotate pod app-pod description="My FastAPI app"

# Label (add/modify labels)
kubectl label pod app-pod tier=frontend

# ============================================
# DELETE
# ============================================

# Delete specific resource
kubectl delete pod app-pod
# ReplicaSet Controller will recreate it if it's part of a Deployment!

# Delete by file
kubectl delete -f deployment-controller-demo.yaml
# Deletes everything defined in the file

# Delete by label
kubectl delete pods -l app=fastapi
# Deletes all pods with label app=fastapi

# Delete deployment (cascading delete)
kubectl delete deployment fastapi-deployment
# Also deletes: ReplicaSet, all Pods

# Delete namespace (deletes everything inside)
kubectl delete namespace demo-ns

# Force delete stuck pod
kubectl delete pod stuck-pod --force --grace-period=0
# Use sparingly! Can cause resource leaks
```

**🔍 Understanding kubectl apply:**

```
Local YAML File          etcd (cluster state)
┌─────────────┐          ┌─────────────┐
│ replicas: 5 │          │ replicas: 3 │
│ image: v2   │          │ image: v1   │
└─────────────┘          └─────────────┘
       │                        │
       └────► kubectl apply ────┘
                    │
                    ▼
            Calculates diff:
            - Change replicas: 3 → 5
            - Change image: v1 → v2
                    │
                    ▼
            Sends PATCH to API server
                    │
                    ▼
            Controllers reconcile
```

**💡 Dry Run - Test Without Applying:**

```bash
# Client-side dry run (validates YAML syntax)
kubectl apply -f deployment.yaml --dry-run=client
# Fast, but doesn't catch cluster-specific issues

# Server-side dry run (validates against cluster)
kubectl apply -f deployment.yaml --dry-run=server
# Slower, but catches issues like: quota exceeded, name conflicts

# Generate YAML without creating
kubectl create deployment test --image=nginx --dry-run=client -o yaml
# Useful for learning YAML structure!
```

### 4.2 Advanced YAML Manifests

**complete-app.yaml**
```yaml
# ===========================================
# NAMESPACE - Logical isolation boundary
# ===========================================
apiVersion: v1
kind: Namespace
metadata:
  name: fastapi-prod
  labels:
    environment: production
    
---
# ===========================================
# CONFIGMAP - Non-sensitive configuration
# ===========================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: fastapi-prod
data:
  # Key-value pairs (plain text)
  APP_VERSION: "2.0"
  LOG_LEVEL: "info"
  # Can also store files:
  # config.json: |
  #   {"key": "value"}
  
---
# ===========================================
# SECRET - Sensitive data (base64 encoded)
# ===========================================
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: fastapi-prod
type: Opaque
stringData:  # Automatically base64-encoded by kubectl
  API_KEY: "super-secret-key-123"
  # Alternatively use 'data:' for pre-encoded values:
  # API_KEY: c3VwZXItc2VjcmV0LWtleS0xMjM=
  
---
# ===========================================
# DEPLOYMENT - Manages ReplicaSets & Pods
# ===========================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
  namespace: fastapi-prod
  labels:
    app: fastapi
    version: v2
spec:
  replicas: 3  # Desired number of pods
  
  # Rolling update strategy
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1       # Max 1 extra pod during update
      maxUnavailable: 1 # Max 1 pod unavailable during update
  
  # Which pods does this deployment manage?
  selector:
    matchLabels:
      app: fastapi
  
  # Pod template - blueprint for creating pods
  template:
    metadata:
      labels:
        app: fastapi  # Must match selector above
        version: v2
    spec:
      containers:
      - name: fastapi
        image: fastapi-app:v1
        imagePullPolicy: Never  # Don't pull, use local
        
        ports:
        - containerPort: 8000
          name: http  # Named port (can reference in Service)
        
        # Environment variables
        env:
        - name: APP_VERSION
          valueFrom:
            configMapKeyRef:  # Read from ConfigMap
              name: app-config
              key: APP_VERSION
        - name: API_KEY
          valueFrom:
            secretKeyRef:  # Read from Secret
              name: app-secret
              key: API_KEY
        
        # Resource requests & limits
        resources:
          requests:  # Guaranteed resources (scheduler uses this)
            memory: "128Mi"
            cpu: "100m"
          limits:    # Maximum allowed (cgroup enforces this)
            memory: "256Mi"
            cpu: "500m"
        
        # Liveness probe - "Is the app alive?"
        # If fails, kubelet restarts container
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10  # Wait 10s before first check
          periodSeconds: 10        # Check every 10s
          timeoutSeconds: 1        # Timeout after 1s
          failureThreshold: 3      # Restart after 3 failures
        
        # Readiness probe - "Is the app ready for traffic?"
        # If fails, pod removed from Service endpoints
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
          
---
# ===========================================
# SERVICE - Stable network endpoint
# ===========================================
apiVersion: v1
kind: Service
metadata:
  name: fastapi-service
  namespace: fastapi-prod
spec:
  selector:
    app: fastapi  # Route to pods with this label
  ports:
  - protocol: TCP
    port: 80         # Service port (what clients connect to)
    targetPort: 8000 # Container port (where traffic goes)
  type: LoadBalancer  # In Minikube, creates NodePort + external IP
  # Other types:
  # - ClusterIP (default, internal only)
  # - NodePort (exposes on node IP:port)
  # - LoadBalancer (cloud provider creates load balancer)
```

**🔍 Understanding the Complete Flow:**

```
1. kubectl apply -f complete-app.yaml
   │
   ▼
2. API Server validates and stores in etcd:
   - Namespace
   - ConfigMap
   - Secret
   - Deployment
   - Service
   │
   ▼
3. Deployment Controller:
   - Creates ReplicaSet (fastapi-app-abc123)
   │
   ▼
4. ReplicaSet Controller:
   - Creates 3 Pods
   │
   ▼
5. Scheduler:
   - Assigns each pod to a node
   │
   ▼
6. kubelet (on each node):
   - Pulls image (or uses cached)
   - Mounts ConfigMap & Secret as env vars
   - Starts container
   - Begins health checks (liveness/readiness)
   │
   ▼
7. kube-proxy:
   - Creates iptables rules for Service
   - Routes traffic to healthy pods (readiness probe passed)
   │
   ▼
8. You:
   - Access via: http://<minikube-ip>:<nodeport>
```

**💡 ConfigMap vs Secret:**

```
ConfigMap                    Secret
├─ Non-sensitive data       ├─ Sensitive data
├─ Plaintext in etcd        ├─ Base64 in etcd
├─ Examples:                ├─ Examples:
│  • App version            │  • API keys
│  • Feature flags          │  • Passwords
│  • Config files           │  • Certificates
└─ Visible in logs OK       └─ Hide in logs
```

**⚠️ Important**: Secrets are base64-encoded, NOT encrypted by default!
- Enable encryption at rest in production
- Use external secret managers (HashiCorp Vault, AWS Secrets Manager)

### 4.3 Labels & Selectors - The Glue of Kubernetes

**📚 Why Labels Matter:**

Labels are key-value pairs attached to objects. They're the primary way Kubernetes components find and group resources.

```
┌──────────────────────────────────────────────┐
│  Service: demo-service                       │
│  selector:                                   │
│    app: fastapi                              │
│    env: prod                                 │
│         │                                    │
│         └───────┐                            │
└─────────────────┼────────────────────────────┘
                  │
                  │ "Find all pods with
                  │  app=fastapi AND env=prod"
                  ▼
    ┌─────────────────────────────────┐
    │  Pod 1                          │
    │  labels:                        │
    │    app: fastapi    ✓            │
    │    env: prod       ✓            │
    │    version: v2                  │
    └─────────────────────────────────┘
    
    ┌─────────────────────────────────┐
    │  Pod 2                          │
    │  labels:                        │
    │    app: fastapi    ✓            │
    │    env: staging    ✗            │
    └─────────────────────────────────┘
           │
           └─► Service ignores this pod!
```

```bash
# Deploy complete app (has labels)
kubectl apply -f complete-app.yaml

# ============================================
# QUERY BY LABELS
# ============================================

# Exact match
kubectl get pods -n fastapi-prod -l app=fastapi
# Returns: All pods with label app=fastapi

# Multiple labels (AND logic)
kubectl get pods -n fastapi-prod -l app=fastapi,version=v2
# Returns: Pods with BOTH labels

# Inequality
kubectl get pods -n fastapi-prod -l app!=nginx
# Returns: All pods WITHOUT app=nginx

# Set-based selectors
kubectl get pods -n fastapi-prod -l 'app in (fastapi,nginx)'
# Returns: Pods with app=fastapi OR app=nginx

kubectl get pods -n fastapi-prod -l 'env notin (test,dev)'
# Returns: Pods where env is NOT test or dev

kubectl get pods -n fastapi-prod -l version
# Returns: Pods that HAVE a version label (any value)

kubectl get pods -n fastapi-prod -l '!version'
# Returns: Pods that DON'T have a version label

# ============================================
# MODIFY LABELS
# ============================================

# Add label to existing pod
POD_NAME=$(kubectl get pods -n fastapi-prod -o jsonpath='{.items[0].metadata.name}')
kubectl label pod $POD_NAME -n fastapi-prod tier=frontend
# Pod now has label: tier=frontend

# Update label (overwrite)
kubectl label pod $POD_NAME -n fastapi-prod tier=backend --overwrite
# tier changed from frontend → backend

# Remove label
kubectl label pod $POD_NAME -n fastapi-prod tier-
# tier label removed (note the minus sign)

# Label multiple resources
kubectl label pods -n fastapi-prod -l app=fastapi monitored=true
# Adds monitored=true to all pods with app=fastapi

# ============================================
# SHOW LABELS
# ============================================

# Show all labels in columns
kubectl get pods -n fastapi-prod --show-labels
# Output:
# NAME                  READY   STATUS    LABELS
# fastapi-app-abc-123   1/1     Running   app=fastapi,version=v2,tier=backend

# Show specific label columns
kubectl get pods -n fastapi-prod -L app,version
# Creates columns for 'app' and 'version' labels

# ============================================
# SELECTORS IN YAML
# ============================================

# There are two types of selectors:
```

**1. Equality-based (simple):**
```yaml
selector:
  app: fastapi
  env: prod
```

**2. Set-based (advanced):**
```yaml
selector:
  matchLabels:
    app: fastapi
  matchExpressions:
  - key: env
    operator: In  # In, NotIn, Exists, DoesNotExist
    values:
    - prod
    - staging
  - key: version
    operator: Exists
```

**🔍 Common Label Patterns:**

```yaml
# Recommended labels (from Kubernetes docs)
labels:
  app.kubernetes.io/name: fastapi        # App name
  app.kubernetes.io/instance: prod-123   # Unique instance
  app.kubernetes.io/version: "2.0.1"     # App version
  app.kubernetes.io/component: api       # Component role
  app.kubernetes.io/part-of: ecommerce   # System name
  app.kubernetes.io/managed-by: helm     # Tool managing this
  
  # Environment labels
  environment: production
  tier: backend  # frontend, backend, database
  
  # Team labels
  team: platform
  owner: john.doe@company.com
  
  # Cost tracking
  cost-center: engineering
  project: mobile-app
```

**💡 Label Selectors in Action:**

```bash
# Service uses labels to find pods
kubectl get endpoints fastapi-service -n fastapi-prod
# Shows pod IPs that match service selector
```

**NetworkPolicy uses labels for firewall rules:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
spec:
  podSelector:
    matchLabels:
      app: fastapi  # Apply to these pods
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend  # Allow traffic from these pods
```

**HorizontalPodAutoscaler uses labels:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    name: fastapi-app
  minReplicas: 3
  maxReplicas: 10
```

```bash
# View resources by label
kubectl get all -n fastapi-prod -l app=fastapi
# Shows: Deployment, ReplicaSet, Pods, Services all with app=fastapi
```

**⚠️ Label Best Practices:**

1. **Use consistent naming**: Decide on lowercase-with-dashes or camelCase
2. **Don't use labels for large data**: Labels are stored in etcd, kept small
3. **Use annotations for non-identifying metadata**: Build IDs, Git commits
4. **Plan label strategy early**: Hard to change later when many resources exist
5. **Avoid label conflicts**: Don't reuse label keys for different purposes

### 4.4 Advanced kubectl Commands

**📚 Debugging & Troubleshooting:**

```bash
# ============================================
# DRY RUN - Test Without Applying
# ============================================

# Client-side (validates YAML locally)
kubectl apply -f complete-app.yaml --dry-run=client
# Fast, checks syntax only

# Server-side (validates against cluster)
kubectl apply -f complete-app.yaml --dry-run=server
# Slower, checks quotas, permissions, conflicts

# Diff changes before applying
kubectl diff -f complete-app.yaml
# Shows what would change (like git diff)

# ============================================
# WATCH & MONITOR
# ============================================

# Watch resources update in real-time
kubectl get pods -n fastapi-prod --watch
# Ctrl+C to stop

# Stream events
kubectl get events -n fastapi-prod --watch

# ============================================
# EXEC & INTERACT
# ============================================

# Execute command in container
kubectl exec -n fastapi-prod deployment/fastapi-app -- ls /app
# Runs 'ls /app' in first container of first pod

# Interactive shell
kubectl exec -it -n fastapi-prod deployment/fastapi-app -- /bin/sh
# Opens shell, -it = interactive terminal

# Execute in specific container (if pod has multiple)
kubectl exec -it -n fastapi-prod $POD_NAME -c fastapi -- /bin/sh

# ============================================
# PORT FORWARDING
# ============================================

# Forward local port to service
kubectl port-forward -n fastapi-prod service/fastapi-service 8080:80
# Access at http://localhost:8080
# Ctrl+C to stop

# Forward to pod directly
kubectl port-forward -n fastapi-prod $POD_NAME 8080:8000

# Forward to deployment (picks first pod)
kubectl port-forward -n fastapi-prod deployment/fastapi-app 8080:8000

# Background port forward
kubectl port-forward -n fastapi-prod service/fastapi-service 8080:80 &
# Kill with: pkill -f "kubectl port-forward"

# ============================================
# LOGS
# ============================================

# View logs from pod
kubectl logs -n fastapi-prod $POD_NAME

# Follow logs (like tail -f)
kubectl logs -n fastapi-prod $POD_NAME -f

# Last N lines
kubectl logs -n fastapi-prod $POD_NAME --tail=50

# Logs from all containers in pod
kubectl logs -n fastapi-prod $POD_NAME --all-containers=true

# Logs from previous container (if crashed)
kubectl logs -n fastapi-prod $POD_NAME --previous

# Logs from deployment (all pods)
kubectl logs -n fastapi-prod deployment/fastapi-app --tail=20

# Logs with timestamps
kubectl logs -n fastapi-prod $POD_NAME --timestamps

# Logs since specific time
kubectl logs -n fastapi-prod $POD_NAME --since=1h
kubectl logs -n fastapi-prod $POD_NAME --since=2023-01-01T00:00:00Z

# Stream logs from all pods with label
kubectl logs -n fastapi-prod -l app=fastapi -f

# ============================================
# DEBUG WITH EPHEMERAL CONTAINERS
# ============================================

# Attach debug container to running pod
kubectl debug -n fastapi-prod $POD_NAME -it --image=busybox --target=fastapi
# --target: Share process namespace with this container
# Useful when main container has no debugging tools

# Debug with different image
kubectl debug -n fastapi-prod $POD_NAME -it --image=nicolaka/netshoot

# Create copy of pod for debugging
kubectl debug -n fastapi-prod $POD_NAME -it --copy-to=debug-pod --image=busybox

# ============================================
# FILE OPERATIONS
# ============================================

# Copy file FROM pod TO local
kubectl cp -n fastapi-prod $POD_NAME:/app/app.py ./app-backup.py

# Copy file FROM local TO pod
kubectl cp -n fastapi-prod ./local-file.txt $POD_NAME:/tmp/

# Copy from specific container
kubectl cp -n fastapi-prod $POD_NAME:/app/logs.txt ./logs.txt -c fastapi

# ============================================
# RESOURCE USAGE
# ============================================

# Node resource usage
kubectl top nodes
# Shows: CPU, Memory usage per node

# Pod resource usage
kubectl top pods -n fastapi-prod
# Shows: CPU, Memory usage per pod

# Sort by CPU
kubectl top pods -n fastapi-prod --sort-by=cpu

# Sort by memory
kubectl top pods -n fastapi-prod --sort-by=memory

# All namespaces
kubectl top pods --all-namespaces

# ============================================
# CONTEXT & NAMESPACE
# ============================================

# View current context
kubectl config current-context
# Shows: minikube

# Set default namespace (avoid typing -n every time)
kubectl config set-context --current --namespace=fastapi-prod

# List all contexts
kubectl config get-contexts

# Switch context
kubectl config use-context minikube

# View kubeconfig
kubectl config view

# ============================================
# EXPLAIN - Built-in Documentation
# ============================================

# Explain resource type
kubectl explain pod
# Shows: What a Pod is, fields available

# Explain nested field
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain deployment.spec.strategy.rollingUpdate

# Recursive (show all subfields)
kubectl explain pod.spec.containers --recursive

# This is your best friend for learning YAML structure!

# ============================================
# WAIT - Synchronous Operations
# ============================================

# Wait for condition
kubectl wait --for=condition=ready pod -l app=fastapi -n fastapi-prod --timeout=60s
# Blocks until all pods are ready or timeout

# Wait for deletion
kubectl delete pod $POD_NAME -n fastapi-prod
kubectl wait --for=delete pod/$POD_NAME -n fastapi-prod --timeout=30s

# Useful in scripts to ensure resource is ready before proceeding
```

**🔍 Real-World Debugging Workflow:**

```bash
# Problem: "My app isn't working!"

# Step 1: Check pod status
kubectl get pods -n fastapi-prod
# STATUS: CrashLoopBackOff, ImagePullBackOff, Pending?

# Step 2: Describe pod (most informative)
kubectl describe pod $POD_NAME -n fastapi-prod
# Look at:
# - Events (bottom of output) - shows what went wrong
# - Conditions - Ready, ContainersReady, PodScheduled
# - Status - Reason for current state

# Step 3: Check logs
kubectl logs $POD_NAME -n fastapi-prod
# Look for: Stack traces, error messages
kubectl logs $POD_NAME -n fastapi-prod --previous  # If crashed

# Step 4: Check service endpoints
kubectl get endpoints fastapi-service -n fastapi-prod
# Are pods listed? If not, label selector is wrong

# Step 5: Exec into pod
kubectl exec -it $POD_NAME -n fastapi-prod -- /bin/sh
# Test connectivity: curl, ping, nslookup
# Check files: ls, cat
# Check environment: env

# Step 6: Check events
kubectl get events -n fastapi-prod --sort-by='.lastTimestamp'
# Shows chronological history of what happened

# Step 7: Network debugging
kubectl run -it --rm debug --image=nicolaka/netshoot -- /bin/bash
# Inside: curl, dig, nslookup, traceroute
curl http://fastapi-service.fastapi-prod.svc.cluster.local

# Step 8: Check resource usage
kubectl top pod $POD_NAME -n fastapi-prod
# Is pod using too much memory? (OOMKilled)
# Is CPU throttled?
```

**💡 Pro Tips:**

```bash
# Alias common commands (add to ~/.bashrc or ~/.zshrc)
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kl='kubectl logs'
alias kd='kubectl describe'
alias ke='kubectl exec -it'

# Use stern for multi-pod log streaming (install separately)
# stern -n fastapi-prod fastapi
# Shows logs from all pods matching 'fastapi' with color coding

# Use kubectx/kubens for context/namespace switching
# kubens fastapi-prod  # Switch to namespace
# kubectx minikube     # Switch to context

# JSON processing with jq
kubectl get pods -n fastapi-prod -o json | jq '.items[] | {name: .metadata.name, status: .status.phase}'

# Watch with color
watch -n 1 --color 'kubectl get pods -n fastapi-prod'
```

### 4.5 YAML Tips & Tricks

```bash
# ============================================
# EXTRACT YAML FROM RUNNING RESOURCES
# ============================================

# Get running resource as YAML
kubectl get deployment -n fastapi-prod fastapi-app -o yaml > backup.yaml
# Useful for backing up or learning from existing resources

# Clean version (remove status, managed fields)
kubectl get deployment fastapi-app -n fastapi-prod -o yaml \
  | grep -v '^\s*creationTimestamp\|resourceVersion\|uid\|selfLink\|status\|managedFields' \
  > clean.yaml

# ============================================
# EDIT RESOURCES DIRECTLY
# ============================================

# Edit in your default editor (set KUBE_EDITOR env var)
kubectl edit deployment -n fastapi-prod fastapi-app
# Opens YAML in editor
# Changes take effect when you save and quit
# Uses your $EDITOR or $KUBE_EDITOR environment variable

# Set editor temporarily
KUBE_EDITOR="nano" kubectl edit deployment fastapi-app -n fastapi-prod

# ============================================
# EXPLAIN - YOUR YAML TEACHER
# ============================================

# Explain any resource type
kubectl explain pod
# Shows: apiVersion, kind, metadata, spec, status

# Explain nested fields
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.resources
kubectl explain deployment.spec.strategy.rollingUpdate

# Show all subfields recursively
kubectl explain pod --recursive
kubectl explain deployment.spec --recursive

# Example workflow for learning:
# 1. kubectl explain deployment > deployment-docs.txt
# 2. kubectl explain deployment.spec.template > template-docs.txt
# 3. Read and understand each field

# ============================================
# VALIDATE YAML
# ============================================

# Validate without creating (client-side)
kubectl apply -f my-app.yaml --validate=true --dry-run=client
# Checks: Syntax, required fields

# Validate against cluster (server-side)
kubectl apply -f my-app.yaml --dry-run=server
# Checks: Syntax, permissions, quotas, conflicts

# Use kubeval (install separately)
# kubeval my-app.yaml
# Validates against Kubernetes OpenAPI schema

# Use kubeconform (faster than kubeval)
# kubeconform my-app.yaml

# ============================================
# APPLY MULTIPLE FILES
# ============================================

# Apply all YAMLs in directory
kubectl apply -f ./kubernetes/

# Apply all YAMLs recursively
kubectl apply -f ./configs/ --recursive

# Apply multiple files
kubectl apply -f namespace.yaml -f deployment.yaml -f service.yaml

# Apply from URL (useful for installing tools)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# ============================================
# KUSTOMIZE - Template-Free Customization
# ============================================

# Apply with kustomize
kubectl apply -k ./overlays/production/

# Example kustomize structure:
# base/
#   ├── deployment.yaml
#   ├── service.yaml
#   └── kustomization.yaml
# overlays/
#   ├── development/
#   │   └── kustomization.yaml  (replicas: 1)
#   └── production/
#       └── kustomization.yaml  (replicas: 10)

# kustomization.yaml example:
# apiVersion: kustomize.config.k8s.io/v1beta1
# kind: Kustomization
# resources:
# - ../../base
# patchesStrategicMerge:
# - deployment-patch.yaml
# namespace: production

# Preview kustomize output
kubectl kustomize ./overlays/production/

# ============================================
# YAML GENERATION SHORTCUTS
# ============================================

# Generate YAML without creating resource
kubectl create deployment my-app --image=nginx --dry-run=client -o yaml

# Generate pod YAML
kubectl run my-pod --image=nginx --dry-run=client -o yaml

# Generate service YAML
kubectl create service clusterip my-service --tcp=80:8080 --dry-run=client -o yaml

# Generate namespace YAML
kubectl create namespace my-namespace --dry-run=client -o yaml

# Generate ConfigMap from file
kubectl create configmap my-config --from-file=config.json --dry-run=client -o yaml

# Generate Secret from literal
kubectl create secret generic my-secret --from-literal=password=secret123 --dry-run=client -o yaml

# Pipe to file
kubectl create deployment my-app --image=nginx --dry-run=client -o yaml > deployment.yaml

# ============================================
# ADVANCED YAML TECHNIQUES
# ============================================

# Multi-document YAML (separate with ---)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: test
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: test
spec:
  containers:
  - name: app
    image: nginx
EOF

# Use here-doc for inline YAML
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: inline-pod
spec:
  containers:
  - name: nginx
    image: nginx
EOF

# Replace resource (delete + create)
kubectl replace -f deployment.yaml
# vs apply (patch)
kubectl apply -f deployment.yaml

# Replace and force (delete + create, even if no changes)
kubectl replace -f deployment.yaml --force

# ============================================
# YAML DEBUGGING
# ============================================

# Common YAML mistakes:
```

**1. Indentation (use 2 spaces, not tabs!):**
```yaml
# ❌ WRONG:
spec:
	containers:  # Tab used

# ✅ CORRECT:
spec:
  containers:  # 2 spaces
```

**2. Quotes around numbers/booleans:**
```yaml
# ❌ WRONG:
replicas: "3"      # String, not number
enabled: "true"    # String, not boolean

# ✅ CORRECT:
replicas: 3
enabled: true
```

**3. Missing --- separator in multi-doc YAML:**
```yaml
# ❌ WRONG:
apiVersion: v1
kind: Namespace
apiVersion: v1  # Parser thinks this is a field of Namespace
kind: Pod

# ✅ CORRECT:
apiVersion: v1
kind: Namespace
---
apiVersion: v1
kind: Pod
```

**4. Forgetting matchLabels in selector:**
```yaml
# ❌ WRONG:
selector:
  app: fastapi  # Equality-based (deprecated for Deployments)

# ✅ CORRECT:
selector:
  matchLabels:
    app: fastapi
```

**5. Label mismatch:**
```yaml
# ❌ WRONG:
selector:
  matchLabels:
    app: fastapi
template:
  metadata:
    labels:
      app: backend  # Doesn't match!

# ✅ CORRECT:
selector:
  matchLabels:
    app: fastapi
template:
  metadata:
    labels:
      app: fastapi  # Matches!
```

---

### YAML Best Practices

**1. Always specify versions** - Understand which version: v1, apps/v1, batch/v1

**2. Use resource requests & limits:**
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

**3. Add health checks:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
```

**4. Use namespaces:**
```yaml
metadata:
  namespace: production  # Don't use default
```

**5. Add labels consistently:**
```yaml
labels:
  app: myapp
  version: v1
  environment: production
```

**6. Use ConfigMaps/Secrets (don't hardcode):**
```yaml
# ❌ BAD:
env:
- name: API_KEY
  value: "hardcoded-secret"  # DON'T!

# ✅ GOOD:
env:
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: app-secrets
      key: api-key
```

**7. Add resource documentation:**
```yaml
metadata:
  annotations:
    description: "FastAPI backend service"
    contact: "team@example.com"
    version: "2.0.1"
```

**8. Use rolling updates:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0  # Zero downtime
```

**9. Set pod disruption budgets:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-pdb
spec:
  minAvailable: 2  # At least 2 pods always running
  selector:
    matchLabels:
      app: fastapi
```

**🎯 Complete Example - Production-Ready YAML:**

```yaml
---
# Namespace isolation
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    environment: production
    
---
# ConfigMap for configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
  annotations:
    description: "Application configuration"
data:
  LOG_LEVEL: "info"
  MAX_WORKERS: "4"
  
---
# Secret for sensitive data
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: production
type: Opaque
stringData:
  database-password: "change-me-in-prod"
  api-key: "secret-key-here"
  
---
# Deployment with best practices
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
  namespace: production
  labels:
    app: fastapi
    version: v2
  annotations:
    description: "FastAPI backend API"
    contact: "team@company.com"
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime
  selector:
    matchLabels:
      app: fastapi
  template:
    metadata:
      labels:
        app: fastapi
        version: v2
    spec:
      # Security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      
      containers:
      - name: fastapi
        image: fastapi-app:v2
        imagePullPolicy: IfNotPresent
        
        ports:
        - name: http
          containerPort: 8000
          protocol: TCP
        
        # Environment from ConfigMap and Secret
        env:
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-password
        
        # Resource management
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
        
        # Health checks
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        
        # Security
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        
        # Temporary storage
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      
      volumes:
      - name: tmp
        emptyDir: {}
      
---
# Service
apiVersion: v1
kind: Service
metadata:
  name: fastapi-service
  namespace: production
  labels:
    app: fastapi
spec:
  type: ClusterIP
  selector:
    app: fastapi
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: http
    
---
# Pod Disruption Budget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: fastapi
```

This production-ready YAML includes:
- Security best practices
- Resource limits
- Health checks
- Zero-downtime updates
- High availability
- Proper secret management

---

## Verification & Testing Checklist

### Complete Lab Verification

```bash
# 1. Verify Minikube is running
minikube status
# Should show: host, kubelet, apiserver all "Running"

# 2. Check all namespaces
kubectl get namespaces

# 3. List all resources in fastapi-prod namespace
kubectl get all -n fastapi-prod

# 4. Test the application
kubectl port-forward -n fastapi-prod service/fastapi-service 8080:80 &
curl http://localhost:8080
# Should return: {"message":"Hello from Kubernetes!", ...}

# 5. View comprehensive cluster info
kubectl cluster-info dump > cluster-dump.txt

# 6. Check Minikube resources
minikube ssh
free -h  # Check memory
df -h    # Check disk
exit

# 7. Clean up
kubectl delete namespace fastapi-prod
kubectl delete -f network-test-pod.yaml
kubectl delete -f service-network-demo.yaml

# 8. Stop Minikube (optional - keeps your work if you don't stop)
minikube stop

# 9. Delete Minikube cluster (warning: destroys everything!)
# minikube delete  # Only if you want to start fresh
```

---

## Key Concepts Summary

### Docker/OCI
- **Images**: Immutable templates with layers (base OS, dependencies, app code)
- **Layers**: Each Dockerfile instruction creates a layer; cached for efficiency
- **Registries**: Store and distribute images (Docker Hub, local registry, Minikube cache)

### Linux & Networking
- **Namespaces**: Isolate processes, network, mounts (basis of containers)
- **cgroups**: Limit and monitor resource usage (CPU, memory)
- **iptables**: Packet filtering and NAT (used by kube-proxy for services)
- **DNS**: Service discovery via CoreDNS (service-name.namespace.svc.cluster.local)

### K8s Architecture
- **API Server**: Central control plane component, REST API
- **etcd**: Distributed key-value store for cluster state
- **Scheduler**: Assigns pods to nodes based on resources
- **Controller Manager**: Maintains desired state (deployments, replicasets)

### kubectl & YAML
- **CRUD**: create, get, describe, edit, delete
- **Labels**: Key-value pairs for organizing resources
- **Selectors**: Query resources by labels
- **Manifests**: Declarative YAML definitions of desired state

---

## Next Steps

1. Practice each section multiple times
2. Break things intentionally to learn troubleshooting
3. Read pod/deployment logs to understand failures
4. Experiment with different label selectors
5. Try modifying YAML and observe behavior changes

## Additional Resources

```bash
# Official docs
kubectl explain <resource>
kubectl explain pod.spec.containers --recursive

# API reference
kubectl api-resources
kubectl api-versions
```

---

## 🎯 Understanding Minikube vs Production Kubernetes

### **Minikube (What You're Using):**
- **Single-node cluster** - Control plane and workloads on same machine
- **Local development** - Not for production use
- **Limited resources** - Uses your laptop/desktop CPU and RAM
- **Easy setup** - Perfect for learning and testing
- **No high availability** - If node goes down, everything stops

### **Production Kubernetes:**
- **Multi-node cluster** - Separate control plane and worker nodes
- **High availability** - Multiple control plane nodes (3 or 5)
- **Distributed** - Workloads spread across many nodes
- **Scalable** - Add/remove nodes as needed
- **Cloud or on-premise** - AWS EKS, Google GKE, Azure AKS, or self-hosted

### **Example: Production Cluster Architecture**
```
Control Plane (3 nodes for HA)
├─ master-1: API Server, etcd, Scheduler, Controller Manager
├─ master-2: API Server, etcd, Scheduler, Controller Manager
└─ master-3: API Server, etcd, Scheduler, Controller Manager

Worker Nodes (Many nodes)
├─ worker-1: kubelet, kube-proxy, Container Runtime, Your Pods
├─ worker-2: kubelet, kube-proxy, Container Runtime, Your Pods
├─ worker-3: kubelet, kube-proxy, Container Runtime, Your Pods
└─ ... (can scale to hundreds or thousands of nodes)
```

**What you learned in Minikube applies 100% to production!** The concepts are identical; only the scale differs.