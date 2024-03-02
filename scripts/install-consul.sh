#!/bin/bash

set -e

eval "$(cat .env)"
eval "$(cat .k8sImages.env)"

export CHART_PATH="$1"
export CONSUL_VERSION="$2"
export K8s_VERSION="$3"

CLUSTER_CONTEXTS=("$CLUSTER1_CONTEXT")

export KUBECONFIG=.secrets/kubeconfig

# Define a function to check if a Helm release is installed
is_helm_release_installed() {
  local release_name="$1"
  local namespace="$2"
  local cluster_context="$3"

  # Run 'helm list' and check if the release exists in the specified namespace
  if helm list -n "$namespace" --kube-context "$cluster_context" | grep -qE "^$release_name\s"; then
    return 0 # Return 0 if the release is installed
  else
    return 1 # Return 1 if the release is not installed
  fi
}

# oc import-image hashicorp/consul-enterprise:1.16.5-ent-ubi --from=registry.connect.redhat.com/hashicorp/consul-enterprise:1.16.5-ent-ubi --confirm
import_redhat_images() {
  local cluster_context="$1"

  echo "install-consul: importing redhat registry images for consul, consul-k8s, and consul-dataplane"
  echo "    >- ${CONSUL_IMAGE}"
  echo "    >- ${CONSUL_K8S_IMAGE}"
  echo "    >- ${CONSUL_K8S_DP_IMAGE}"
  oc --context "$cluster_context" import-image "${CONSUL_IMAGE#registry.connect.redhat.com/}" --from="${CONSUL_IMAGE}" --confirm 2>&1 || {
    echo "install-consul: failed to import $CONSUL_IMAGE"
    exit 1
  }
  echo "install-consul: successfully imported $CONSUL_IMAGE"
  oc --context "$cluster_context" import-image "${CONSUL_K8S_IMAGE#registry.connect.redhat.com/}" --from="${CONSUL_K8S_IMAGE}" --confirm &>/dev/null || {
    echo "install-consul: failed to import $CONSUL_K8S_IMAGE"
    exit 1
  }
  echo "install-consul: successfully imported $CONSUL_K8S_IMAGE"
  oc --context "$cluster_context" import-image "${CONSUL_K8S_DP_IMAGE#registry.connect.redhat.com/}" --from="${CONSUL_K8S_DP_IMAGE}" --confirm &>/dev/null || {
    echo "install-consul: failed to import $CONSUL_K8S_DP_IMAGE"
    exit 1
  }
  echo "install-consul: successfully imported $CONSUL_K8S_DP_IMAGE"
}

create_secret() {
  local cluster_context="$1"
  local namespace="$2"
  local secret_name="$3"
  local key="$4"

  echo "install-consul: creating generic secret $secret_name in ns $namespace | $cluster_context"
  oc --context "$cluster_context" -n "$namespace" create secret generic "$secret_name" --from-literal="key=$key" >/dev/null 2>&1 || true
}

for cluster_context in "${CLUSTER_CONTEXTS[@]}"; do
  import_redhat_images "$cluster_context"
  create_secret "$cluster_context" "consul" "license" "$CONSUL_LICENSE"
done
clear

export HELM_RELEASE_NAME=consul
if ! is_helm_release_installed "${HELM_RELEASE_NAME}" "${CONSUL_NS}" "$CLUSTER1_CONTEXT"; then
  echo "install-consul: running helm install | release: ${HELM_RELEASE_NAME} | context: $CLUSTER1_CONTEXT"
  helm install ${HELM_RELEASE_NAME} "$CHART_PATH" \
    --namespace "$CONSUL_NS" \
    --version "$K8s_VERSION" \
    --values consul/values-ent.yaml \
    --set global.datacenter=dc1 \
    --set global.image="${CONSUL_IMAGE}" \
    --set global.imageK8S="${CONSUL_K8S_IMAGE}" \
    --set global.imageConsulDataplane="${CONSUL_K8S_DP_IMAGE}" \
    --set meshGateway.replicas=1 \
    --kube-context "$CLUSTER1_CONTEXT"
  echo "install-consul: waiting for mesh-gateway to become ready... | $CLUSTER1_CONTEXT"
  openshift/kubectl wait \
    --context "$CLUSTER1_CONTEXT" \
    --namespace "$CONSUL_NS" \
    --for=condition=ready pod \
    --selector=app=consul,component=mesh-gateway \
    --timeout=90s
else
  echo "install-consul: consul already installed | release: $HELM_RELEASE_NAME"
fi