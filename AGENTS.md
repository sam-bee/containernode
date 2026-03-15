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

## Tailscale Serve Configuration Deployment

The repository contains the authoritative configuration for the Tailscale Serve routing layer used by the `containernode` host.

### Overview

Tailscale Serve exposes selected internal services from `containernode` to the tailnet using hostname-based routing. The Serve configuration is stored in this repository and deployed automatically whenever changes are pushed to the `main` branch.

Deployment is triggered by GitHub Actions and executed remotely on the production server over Tailscale.

### Source of Truth

The canonical Tailscale Serve configuration is stored in this repository as a huJSON configuration file compatible with the `tailscale serve set-config` command.

The repository also contains a deployment script responsible for applying the configuration on the production host.

### Deployment Flow

When a commit is pushed to the `main` branch:

1. A GitHub Actions workflow is triggered.
2. The workflow joins the tailnet using a Tailscale ephemeral node.
3. The workflow connects to the production host using `tailscale ssh`.
4. The workflow executes a deployment script that is stored in this repository.

### Server-side Deployment Process

The deployment script runs on `containernode` and performs the following steps:

1. Updates a local clone of this repository located on the server.
2. Checks out the latest state of the `main` branch.
3. Locates the Tailscale Serve configuration file.
4. Applies the configuration using: `tailscale serve set-config <config-file> --all`


The script exits with a non-zero status if any step fails.

Because the GitHub Actions workflow executes the script remotely, any failure causes the workflow to fail and visibly breaks the deployment.

### Interaction With Kubernetes GitOps

The Tailscale Serve configuration is independent of the Kubernetes GitOps system managed by Flux.

Flux reconciles Kubernetes resources inside the cluster, while the Tailscale Serve configuration manages host-level routing for services exposed through the tailnet.

Both reconciliation processes may run at approximately the same time when a commit is pushed to `main`.

The two systems operate on separate layers and do not share state.

### Idempotency

The deployment script is designed to be idempotent. Re-running the script results in the same configuration state being applied to the Tailscale Serve subsystem.

This allows deployments to be safely retried if a workflow is re-run.
