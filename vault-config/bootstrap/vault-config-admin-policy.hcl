# Allows vault-config-operator CRs in vault-admin to manage app policies and Kubernetes auth roles.
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/kubernetes/config" {
  capabilities = ["read"]
}
