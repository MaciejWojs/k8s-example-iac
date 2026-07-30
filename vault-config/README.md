# Vault configuration (GitOps)

Policies and Kubernetes auth **roles** for the example app are managed with [Vault Config Operator](https://github.com/redhat-cop/vault-config-operator) (VCO). **Secret values are not synced** — you add them manually in Vault after each fresh cluster.

ArgoCD applications (sync waves):

| App | Wave | Purpose |
|-----|------|---------|
| `k8s-example-cert-manager` | -25 | TLS for VCO webhooks (required on Kind) |
| `k8s-example-vault-config-operator` | -20 | VCO controller |
| `k8s-example-vault` | -15 | Vault server (dev) + Agent Injector |
| `k8s-example-vault-config` | -8 | `Policy` + `KubernetesAuthEngineRole` CRs |
| `k8s-example` | 0 | Backend, migrate/seed jobs, frontend |

## What VCO manages (in Git)

| Vault | Kubernetes workload | ServiceAccount | KV path (values **manual**) |
|-------|---------------------|----------------|-----------------------------|
| Role `myapp` | Backend Deployment | `backend-sa` | `secret/myapp` |
| Role `migrate` | PreSync migrate Job (Agent Injector) | `migrate-sa` | `secret/migrate` |
| Role `seed` | PreSync seed Job | `seed-sa` | `secret/seed` |

Policies allow **read** on the matching `secret/data/<name>` path only.

## One-time bootstrap (per cluster)

VCO authenticates each CR with the `vault-config-admin` ServiceAccount and Vault role `policy-admin`. That role must exist **before** CRs can reconcile.

1. Ensure Vault and `k8s-example-vault-config` are synced in ArgoCD (`vault-admin` namespace + `vault-config-admin` SA).
2. From this repository root (`iac/`):

```bash
chmod +x vault-config/bootstrap/bootstrap.sh
./vault-config/bootstrap/bootstrap.sh
```

3. Wait until VCO reports success:

```bash
kubectl get policy,kubernetesauthenginerole -n vault-admin
kubectl describe policy myapp -n vault-admin   # look for Ready / ReconcileSuccessful
```

If CRs stay in error, confirm `VAULT_ADDR` on the operator (`vault-config-operator/values.yaml`) and re-run bootstrap.

## Manual KV secrets (required for backend, migrate, seed)

Vault dev mode enables KV v2 at mount `secret/` by default. Paths in the app use the API form `secret/data/<name>`.

### 1. Get PostgreSQL connection string

CloudNative-PG creates an application secret for cluster `cluster-example`:

```bash
kubectl get secret cluster-example-app -n k8s-example -o jsonpath='{.data.uri}' | base64 -d && echo
```

Use that value as `DATABASE_URL` (Atlas migrate appends `?sslmode=disable` in the Job).

### 2. Write secrets

Port-forward Vault (optional if using `kubectl exec` into the Vault pod):

```bash
kubectl port-forward svc/k8s-example-vault -n vault 8200:8200
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(kubectl exec -n vault k8s-example-vault-0 -- printenv VAULT_DEV_ROOT_TOKEN_ID)
```

**Backend** (`USE_VAULT`, role `myapp`, path `secret/data/myapp`):

```bash
vault kv put secret/myapp \
  DATABASE_URL='postgresql://app:PASSWORD@cluster-example-rw.k8s-example.svc:5432/app' \
  DEVELOPMENT=true \
  PERFORM_DATABASE_MIGRATIONS=false \
  PERFORM_DATABASE_SEEDING=false
```

Replace `DATABASE_URL` with the URI from `cluster-example-app`.

**Migrate job** (Vault Agent Injector, role `migrate`, template reads `DATABASE_URL`):

```bash
vault kv put secret/migrate \
  DATABASE_URL='postgresql://app:PASSWORD@cluster-example-rw.k8s-example.svc:5432/app'
```

**Seed job** (role `seed`, path `secret/data/seed` — same env contract as backend):

```bash
vault kv put secret/seed \
  DATABASE_URL='postgresql://app:PASSWORD@cluster-example-rw.k8s-example.svc:5432/app' \
  DEVELOPMENT=true \
  PERFORM_DATABASE_MIGRATIONS=false \
  PERFORM_DATABASE_SEEDING=false
```

### 3. Sync the application

Sync `k8s-example` in ArgoCD (or wait for auto-sync). Order at runtime:

1. PreSync wave 0: `atlas-migrate` (injector + `migrate` role)
2. PreSync wave 1: `seed-database` (Vault login + `seed` role)
3. Backend Deployment starts with `myapp` role

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Migrate pod without `/vault/secrets/database.env` | Injector enabled (`vault/values.yaml`), role `migrate`, secret `secret/migrate` |
| Backend exits on Vault init | `vault kv get secret/myapp`, role `myapp`, SA `backend-sa` |
| Seed job fails | `secret/seed` keys match [backend env schema](https://github.com/MaciejWojs/k8s-example-backend) (`DATABASE_URL`, `DEVELOPMENT`, …) |
| `ServiceMonitor` SyncFailed on operator | Set `enableMonitoring: false` in `vault-config-operator/values.yaml` |
| `webhook-server-cert` not found / webhook connection refused | Sync **`k8s-example-cert-manager`** first; set `enableCertManager: true` in operator values (vanilla K8s, not OpenShift) |
| Policy CR not ready | Run `bootstrap.sh`; operator logs in `vault-config-operator` |

## Changing policies or roles

Edit files under `vault-config/policies/` or `vault-config/roles/`, commit, push — ArgoCD syncs CRs and VCO updates Vault. **Do not** put secret values in Git.
