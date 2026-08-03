# K8s Example Infrastructure as Code

Kubernetes manifests and Helm values for deploying the **k8s-example** stack (Nuxt frontend, Bun/Hono backend API, PostgreSQL) with **Argo CD** GitOps. Application source code lives in separate repositories ([backend API](https://github.com/MaciejWojs/k8s-example-backend), [frontend](https://github.com/MaciejWojs/k8s-example-frontend)); this repo defines only cluster resources and sync configuration.

Published as [k8s-example-iac](https://github.com/MaciejWojs/k8s-example-iac) on GitHub.

## Features

- **GitOps with Argo CD**: Automated sync, prune, and self-heal for all components.
- **Gateway API ingress**: Standard Gateway API CRDs plus [NGINX Gateway Fabric](https://github.com/nginx/nginx-gateway-fabric) (not the legacy NGINX Ingress Controller).
- **PostgreSQL**: [CloudNativePG](https://cloudnative-pg.io/) operator (Helm chart) and a `Cluster` with two instances.
- **Secrets**: HashiCorp Vault in **dev mode** with **Vault Agent Injector**; `DATABASE_URL` and app config are read from KV paths at runtime (no Kubernetes `Secret` manifests in Git).
- **Database lifecycle**: Argo CD **PreSync** Jobs run Atlas migrations and `bun seed` before the backend Deployment syncs.

## Repository layout

| Path | Purpose |
|------|---------|
| `kind-config.yaml` | Local Kind cluster: `ingress-ready` label and host ports 80/443 |
| `argocd/namespace.yaml` | `argocd` namespace |
| `argocd/apps/` | Argo CD `Application` manifests (see below) |
| `infrastructure/postgres/` | CloudNativePG `Cluster` (`cluster-example`) |
| `k8s-example/` | App namespace workloads: frontend, backend, Gateway, HTTPRoute, migrate/seed Jobs |
| `nginx-gateway-fabric/values.yaml` | Helm values for NGINX Gateway Fabric (host ports, control-plane scheduling) |
| `vault/` | Vault namespace stub and Helm values (`server.dev`, `injector.enabled`) |

### Argo CD applications (`argocd/apps/`)

Applications use **sync waves** so dependencies install in order:

| Application | Sync wave | Source |
|-------------|-----------|--------|
| `k8s-example-gateway-api` | -25 | Gateway API CRDs from NGINX Gateway Fabric repo |
| `k8s-example-nginx-gateway-fabric` | -20 | Helm chart `nginx-gateway-fabric` + `nginx-gateway-fabric/values.yaml` |
| `k8s-example-vault` | -15 | HashiCorp Vault Helm chart + `vault/values.yaml` |
| `k8s-example-infrastructure` | -10 | CloudNativePG chart + `infrastructure/postgres/` |
| `k8s-example` | 0 | `k8s-example/` (excludes `*secret-example*.yaml`) |

All applications target this repository (`repoURL: https://github.com/MaciejWojs/k8s-example-iac.git`, `targetRevision: HEAD`) unless they pull external charts or CRDs.

## Architecture

```text
Host :80 / :443 (Kind)
        │
        ▼
NGINX Gateway Fabric (namespace nginx-gateway)
        │
        ▼
Gateway k8s-example-gateway (namespace k8s-example)
        │
        ▼
HTTPRoute k8s-example
   /api  → backend-service:3000
   /     → frontend-service:3000

Backend Deployment  ← Vault Agent Injector (secret/data/myapp, role myapp)
PreSync Job atlas-migrate ← injector (secret/data/migrate, role migrate)
PreSync Job seed-database ← injector (secret/data/seed, role seed)

PostgreSQL Cluster cluster-example (CloudNativePG, 2 instances)
```

- **Images**: `ghcr.io/maciejwojs/k8s-example-backend` and `ghcr.io/maciejwojs/k8s-example-frontend` (tags set in manifests).
- **Backend config**: `k8s-example/backend/config/config.yaml` — `USE_VAULT=true`, `VAULT_SECRETS_MODE=injector`, `VAULT_SECRET_PATH=/vault/secrets/database`.
- **Frontend config**: `k8s-example/frontend/config/config.yaml` — `NUXT_PUBLIC_BASE_URL` (e.g. `http://localhost` for Kind on port 80).

For how the backend reads Vault (injector vs API mode), see the [application README](https://github.com/MaciejWojs/k8s-example-backend#hashicorp-vault-integration).

## Prerequisites

- Docker
- [Kind](https://kind.sigs.k8s.io/) (example install):

  ```bash
  go install sigs.k8s.io/kind@v0.32.0
  ```

- `kubectl`

Optional: [Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) for UI/CLI access.

## Local installation (Kind)

Run commands from the root of this repository (`iac/`).

### 1. Create the cluster

```bash
kind create cluster --config ./kind-config.yaml
```

### 2. Install Argo CD

```bash
kubectl apply -f argocd/namespace.yaml
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Register Argo CD applications

```bash
kubectl apply -f argocd/apps/
```

Argo CD will sync Gateway API CRDs, NGINX Gateway Fabric, Vault, CloudNativePG, the PostgreSQL cluster, and the application stack. Wait until infrastructure apps (especially Vault and PostgreSQL) are **Healthy** before the main app sync succeeds.

### 4. Configure Vault (one-time per cluster)

Vault runs in **development mode** with the injector enabled (`vault/values.yaml`). Policies, Kubernetes auth roles (`myapp`, `migrate`, `seed`), and KV data are **not** defined in this repository—you must configure them once so pods in `k8s-example` can authenticate and read secrets.

| KV path (`vault kv put …`) | Vault role | ServiceAccount | Workload |
|----------------------------|------------|----------------|----------|
| `secret/myapp` | `myapp` | `backend-sa` | Backend Deployment |
| `secret/migrate` | `migrate` | `migrate-sa` | PreSync Job `atlas-migrate` |
| `secret/seed` | `seed` | `seed-sa` | PreSync Job `seed-database` |

**Backend and seed** secrets should match the shape expected by the app (injector JSON at `/vault/secrets/database`):

```json
{
  "DATABASE_URL": "postgresql://user:password@cluster-example-rw:5432/app",
  "DEVELOPMENT": "true",
  "PERFORM_DATABASE_MIGRATIONS": "false",
  "PERFORM_DATABASE_SEEDING": "false"
}
```

**Migrate** needs only `DATABASE_URL` (the Job sources it from `/vault/secrets/database.env`).

Wait until the CloudNativePG cluster `cluster-example` is ready before reading credentials:

```bash
kubectl wait --for=condition=Ready cluster/cluster-example -n k8s-example --timeout=300s
```

#### 4.1 Vault CLI session

Install the [Vault CLI](https://developer.hashicorp.com/vault/install) locally, port-forward the server, and use the dev root token (Helm dev server):

```bash
kubectl port-forward -n vault svc/k8s-example-vault 8200:8200
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN="$(kubectl exec -n vault k8s-example-vault-0 -c vault -- \
  printenv VAULT_DEV_ROOT_TOKEN_ID)"
```

#### 4.2 Read `DATABASE_URL` from CloudNativePG

CloudNativePG creates Secret `cluster-example-app` in `k8s-example` with connection fields (`uri`, `username`, `password`, `host`, `port`, `dbname`). The read-write Service is `cluster-example-rw`.

```bash
# Full URI (postgresql://…@cluster-example-rw:5432/…)
export DATABASE_URL="$(kubectl get secret cluster-example-app -n k8s-example \
  -o jsonpath='{.data.uri}' | base64 -d)"

echo "$DATABASE_URL"

# Optional: inspect all keys
kubectl get secret cluster-example-app -n k8s-example -o json | jq -r '.data | keys[]'
```

If you prefer to build the URL manually:

```bash
USER="$(kubectl get secret cluster-example-app -n k8s-example -o jsonpath='{.data.username}' | base64 -d)"
PASS="$(kubectl get secret cluster-example-app -n k8s-example -o jsonpath='{.data.password}' | base64 -d)"
DB="$(kubectl get secret cluster-example-app -n k8s-example -o jsonpath='{.data.dbname}' | base64 -d)"
export DATABASE_URL="postgresql://${USER}:${PASS}@cluster-example-rw:5432/${DB}"
```

#### 4.3 Enable Kubernetes auth and configure the API

Use the Vault server ServiceAccount as the token reviewer:

```bash
export VAULT_SA_NAME="$(kubectl get sa -n vault \
  -l app.kubernetes.io/name=vault,app.kubernetes.io/instance=k8s-example-vault \
  -o jsonpath='{.items[0].metadata.name}')"

vault auth enable kubernetes || true

vault write auth/kubernetes/config \
  kubernetes_host="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')" \
  token_reviewer_jwt="$(kubectl create token -n vault "${VAULT_SA_NAME}" --duration=8760h)" \
  kubernetes_ca_cert="$(kubectl config view --raw \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)"
```

#### 4.4 Policies

```bash
vault policy write myapp-policy - <<'EOF'
path "secret/data/myapp" {
  capabilities = ["read"]
}
EOF

vault policy write migrate-policy - <<'EOF'
path "secret/data/migrate" {
  capabilities = ["read"]
}
EOF

vault policy write seed-policy - <<'EOF'
path "secret/data/seed" {
  capabilities = ["read"]
}
EOF
```

#### 4.5 Roles (bind to ServiceAccounts in `k8s-example`)

```bash
vault write auth/kubernetes/role/myapp \
  bound_service_account_names=backend-sa \
  bound_service_account_namespaces=k8s-example \
  policies=myapp-policy \
  ttl=24h

vault write auth/kubernetes/role/migrate \
  bound_service_account_names=migrate-sa \
  bound_service_account_namespaces=k8s-example \
  policies=migrate-policy \
  ttl=24h

vault write auth/kubernetes/role/seed \
  bound_service_account_names=seed-sa \
  bound_service_account_namespaces=k8s-example \
  policies=seed-policy \
  ttl=24h
```

#### 4.6 Store secrets in KV v2

Dev mode already mounts KV v2 at `secret/`. Values are strings (same as env vars in the app):

```bash
vault kv put secret/myapp \
  DATABASE_URL="${DATABASE_URL}" \
  DEVELOPMENT=true \
  PERFORM_DATABASE_MIGRATIONS=false \
  PERFORM_DATABASE_SEEDING=false

vault kv put secret/seed \
  DATABASE_URL="${DATABASE_URL}" \
  DEVELOPMENT=true \
  PERFORM_DATABASE_MIGRATIONS=false \
  PERFORM_DATABASE_SEEDING=false

vault kv put secret/migrate \
  DATABASE_URL="${DATABASE_URL}"
```

Re-sync or wait for Argo CD on application `k8s-example` if migrate/seed Jobs failed before Vault was ready.

Until Vault is configured, PreSync migrate/seed Jobs and the backend Deployment will fail to obtain credentials.

### 5. Access Argo CD UI (optional)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Open `https://localhost:8080` (accept the self-signed certificate).

### 6. Access the application

With Kind port mapping from `kind-config.yaml`, open:

- `http://localhost/` — frontend
- `http://localhost/api` — backend API

## Configuration

Non-secret settings are in ConfigMaps under `k8s-example/`:

| File | ConfigMap | Notes |
|------|-----------|--------|
| `backend/config/config.yaml` | `backend-config` | Vault injector mode for the API |
| `frontend/config/config.yaml` | `frontend-config` | Public base URL for the Nuxt app |
| `backend/jobs/config/migrate-config.yaml` | — | ServiceAccount `migrate-sa` (PreSync hook) |
| `backend/jobs/config/seed-config.yaml` | `seed-config` | Vault settings for the seed Job |

Image tags and resource limits are set in `backend/backend.yaml`, `frontend/frontend.yaml`, and job manifests. Argo CD image-updater or CI in the app repos may bump those tags on the GitHub remote.

## Secrets management

Kubernetes `Secret` objects for database credentials are **not** committed here. Runtime secrets are expected in **Vault KV** and delivered via **Vault Agent Injector** annotations on the backend Deployment and PreSync Jobs (`k8s-example/backend/`).

Do not commit real credentials to Git. For local development without Kubernetes, use Docker Compose and `.env` in the application repository.

## Related repositories

| Repository | Role |
|------------|------|
| [k8s-example-backend](https://github.com/MaciejWojs/k8s-example-backend) | Backend API, Atlas migrations, seed, container image |
| [k8s-example-frontend](https://github.com/MaciejWojs/k8s-example-frontend) | Nuxt frontend image |
| **k8s-example-iac** (this repo) | Kubernetes manifests, Argo CD, infra charts |
