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
- `argocd`: ArgoCD CLI or running instance for GitOps deployment.

## Architecture Overview
The application is composed of the following services:
- **Frontend**: The user-facing web application.
- **Backend**: The application logic layer, communicating with the frontend and database.
- **PostgreSQL**: The persistent data store for the application.

## Installation and Deployment

### Kubernetes Deployment (Recommended)
To deploy the stack to a Kubernetes cluster:

**A. Prerequisites**
Before deploying, ensure that ArgoCD and Ingress resources are manually installed on your target cluster.

**B. Apply Core Manifest**
Apply the base Kubernetes configuration:
```bash
kubectl apply -f .
```

**C. Configure ArgoCD (GitOps)**
To load the application into ArgoCD, navigate to the `argocd` directory and apply the application manifest:
```bash
cd argocd
kubectl apply -f Application.yaml
```
If using ArgoCD, ensure the `argocd/Application.yaml` is correctly configured to point to this repository and the desired branch (`main`). ArgoCD will handle the continuous synchronization of the state.

## Configuration
Configuration values (like image tags, replica counts, and environment variables) are managed in the respective configuration files within the `k8s-example/` directory.

- `k8s-example-backend-config.yaml`: Backend specific configuration.
- `k8s-example-frontend-config.yaml`: Frontend specific configuration.
- `postgres-config.yaml`: PostgreSQL configuration details.

## Secrets Management
Note that the secrets defined in this repository are for example purposes only. You must manually apply the necessary secrets to your target Kubernetes cluster before deploying the application.