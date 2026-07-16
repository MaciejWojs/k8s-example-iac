# K8s Example Infrastructure as Code

This repository contains Kubernetes manifests and configuration files for deploying a sample application stack. It demonstrates how to manage various components such as frontend, backend, and a PostgreSQL database using Infrastructure as Code (IaC) principles.

## Features

- **Kubernetes Manifest Management**: Defines all necessary Kubernetes resources (Deployments, Services, Ingress, ConfigMaps, Secrets, etc.).
- **Modular Configuration**: Separates configuration (e.g., `k8s-example-backend-config.yaml`) from core definitions for easier management.
- **Database Integration**: Includes setup for a PostgreSQL instance.
- **ArgoCD Integration**: Contains application and namespace definitions for GitOps deployment via ArgoCD.

## Prerequisites

Before deploying this stack, ensure you have the following tools installed and configured:

- `kubectl`: Kubernetes command-line tool.
  ```bash
  sudo snap install kubectl
  ```
- `kind`: Kubernetes-in-Docker cluster creation tool.
  ```bash
  go install sigs.k8s.io/kind@v0.32.0
  ```
- `docker`
- `argocd`: ArgoCD CLI or running instance for GitOps deployment (optional).

## Architecture Overview

The application is composed of the following services:

- **Frontend**: The user-facing web application.
- **Backend**: The application logic layer, communicating with the frontend and database.
- **PostgreSQL**: The persistent data store for the application.

---

# Local Installation

## Required Tools

- Docker
- Kind: Kubernetes-in-Docker cluster creation tool
  ```bash
  go install sigs.k8s.io/kind@v0.32.0
  ```
- kubectl: Kubernetes command-line tool
  ```bash
  sudo snap install kubectl
  ```

## Deploy Application

### 1. Create Cluster

```bash
kind create cluster --config ./kind-config.yaml
```

### 2. Install Nginx Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

### 3. Create ArgoCD Namespace

```bash
kubectl apply -f argocd/namespace.yaml
```

### 4. Install ArgoCD

```bash
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 5. Create Secrets

Based on example secrets:

```bash
cd k8s-example
cp k8s-example-backend-secret-example.yaml k8s-example-backend-secret.yaml
cd -
cd infrastructure
cp postgres-secret-example.yaml postgres-secret.yaml
cd -
```

### 6. Deploy ArgoCD Application

```bash
cd argocd
kubectl apply -f Application.yaml -f Infrastructure-application.yaml
cd -
```

### 7. Deploy Secrets

```bash
cd k8s-example
kubectl apply -f namespace.yaml
kubectl apply -f k8s-example-backend-secret.yaml -n k8s-example
cd -
cd infrastructure
kubectl apply -f postgres-secret.yaml -n k8s-example
cd -
```

### 8. Port-Forward ArgoCD Server

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 9. Retrieve Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## Configuration

Configuration values (like image tags, replica counts, and environment variables) are managed in the respective configuration files within the `k8s-example/` directory.

- `k8s-example-backend-config.yaml`: Backend specific configuration.
- `k8s-example-frontend-config.yaml`: Frontend specific configuration.
- `postgres-config.yaml`: PostgreSQL configuration details.

## Secrets Management

Note that the secrets defined in this repository are for example purposes only. You must manually apply the necessary secrets to your target Kubernetes cluster before deploying the application.