# AGENTS.md

## Project Overview

This repository contains the configuration and infrastructure code for **containernode**, a Kubernetes (k3s) worker/control node used in the ErithC self-hosted infrastructure.

The node runs a collection of self-hosted services and experimental workloads. The cluster is designed to be reproducible and declaratively managed, with infrastructure defined in Git where possible.

The environment prioritizes:

- reproducibility
- minimal manual configuration
- GitOps-style management of services
- compatibility with a small personal cluster

This repository is intended to act as the **source of truth for cluster configuration**.

## Kubernetes API Server

The Kubernetes API server for this environment runs on:

`containernode.[TAILNET_NAME].ts.net:6443`

(If you would like to know the tailnet name, ask the user.)

This node currently acts as the cluster control plane.

Local development machines interact with the cluster using `kubectl` configured to point at this endpoint over the Tailscale network.

---

## Infrastructure Context

The node runs:

- **k3s Kubernetes**
- **Traefik ingress** (k3s default)
- **Tailscale networking**
- **Proxmox VM host environment**
- **NFS / shared storage mounts**

Persistent storage may be backed by network mounts or host-provided volumes.

---

## Repository Layout (Typical)

The repository generally contains:

```
/kubernetes
Kubernetes manifests and service definitions

/helm
Helm charts or Helmfile definitions for services

/scripts
Utility scripts used to deploy or maintain the node

/config
Configuration files for services running in the cluster
```


Exact structure may evolve, but manifests and deployment definitions should remain declarative and version-controlled.

---

## Design Principles

1. **Declarative infrastructure**

   Prefer manifests or Helm over manual configuration.

2. **Small cluster assumptions**

   The system is designed for a single-node or small-node cluster rather than large-scale Kubernetes.

3. **Self-hosted services**

   The cluster may run services such as:

   - blockchain nodes (e.g. Monero)
   - internal tools
   - experimental infrastructure components

4. **Networking**

   - Tailscale is used for secure access
   - services may be exposed via Traefik ingress

---

## Agent Guidance

When modifying this repository:

- Prefer **updating manifests rather than adding imperative scripts**
- Maintain **clear separation between infrastructure and application configs**
- Avoid introducing unnecessary complexity suited only for large clusters
- Assume the environment is **operated by a single developer**

---

## Notes

This repository represents a **live personal infrastructure environment**, so changes should prioritize stability and clarity.

If you'd like, I can also produce a much better version tailored to how your repo is actually structured (Flux, Helmfile, k3s manifests, storage layout, etc.). That one would be significantly more useful for coding agents.