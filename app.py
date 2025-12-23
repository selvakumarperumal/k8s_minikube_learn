from fastapi import FastAPI
import os
import socket

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "Hello from Kubernetes!",
        "hostname": socket.gethostname(),
        "pod_name": os.getenv("HOSTNAME")
        }

@app.get("/health")
def read_health():
    return {"status": "ok"}
