#!/usr/bin/env bash
# One-time bootstrap so Vault Config Operator can reconcile Policy / KubernetesAuthEngineRole CRs.
# Run after Vault and vault-config-admin ServiceAccount exist (ArgoCD app k8s-example-vault-config).
set -euo pipefail

VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_RELEASE="${VAULT_RELEASE:-k8s-example-vault}"
VAULT_ADMIN_NAMESPACE="${VAULT_ADMIN_NAMESPACE:-vault-admin}"
VAULT_ADMIN_SA="${VAULT_ADMIN_SA:-vault-config-admin}"
POLICY_ADMIN_ROLE="${POLICY_ADMIN_ROLE:-policy-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! kubectl get sa "${VAULT_ADMIN_SA}" -n "${VAULT_ADMIN_NAMESPACE}" &>/dev/null; then
  echo "ServiceAccount ${VAULT_ADMIN_NAMESPACE}/${VAULT_ADMIN_SA} not found. Sync ArgoCD app k8s-example-vault-config first."
  exit 1
fi

kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=vault" -n "${VAULT_NAMESPACE}" --timeout=180s

VAULT_POD="$(kubectl get pod -n "${VAULT_NAMESPACE}" -l "app.kubernetes.io/name=vault,component=server" -o jsonpath='{.items[0].metadata.name}')"
ROOT_TOKEN="$(kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- printenv VAULT_DEV_ROOT_TOKEN_ID 2>/dev/null || true)"
if [[ -z "${ROOT_TOKEN}" ]]; then
  echo "Could not read VAULT_DEV_ROOT_TOKEN_ID from Vault pod. Set ROOT_TOKEN and re-run."
  exit 1
fi

KUBE_HOST="https://kubernetes.default.svc:443"
TOKEN_REVIEWER_JWT="$(kubectl create token "${VAULT_RELEASE}" -n "${VAULT_NAMESPACE}" --duration=15m)"
CA_CERT="$(kubectl get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"

vault_exec() {
  kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" vault "$@"
}

vault_write_k8s_config() {
  kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- sh -ec "
    set -e
    cat > /tmp/k8s-ca.crt <<'EOCA'
${CA_CERT}
EOCA
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=${ROOT_TOKEN}
    vault write auth/kubernetes/config \
      kubernetes_host=${KUBE_HOST} \
      token_reviewer_jwt=${TOKEN_REVIEWER_JWT} \
      kubernetes_ca_cert=@/tmp/k8s-ca.crt \
      disable_iss_validation=true
  "
}

if ! vault_exec auth list -format=json | grep -q '"kubernetes/"'; then
  vault_exec auth enable kubernetes
fi

vault_write_k8s_config

kubectl exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${ROOT_TOKEN}" \
  vault policy write vault-config-admin - < "${SCRIPT_DIR}/vault-config-admin-policy.hcl"

vault_exec write auth/kubernetes/role/"${POLICY_ADMIN_ROLE}" \
  bound_service_account_names="${VAULT_ADMIN_SA}" \
  bound_service_account_namespaces="${VAULT_ADMIN_NAMESPACE}" \
  policies=vault-config-admin \
  ttl=1h

echo "Bootstrap complete. Verify operator CRs: kubectl get policy,kubernetesauthenginerole -n ${VAULT_ADMIN_NAMESPACE}"
echo "Then write KV secrets (see vault-config/README.md)."
