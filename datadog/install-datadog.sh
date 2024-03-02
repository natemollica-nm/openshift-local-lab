#!/usr/bin/env bash

set -e

datadogOperatorVersion="$1"

eval "$(cat .ddImages.env)"

CLUSTER_CONTEXTS=("$DATADOG_CONTEXT")

function add_dd_helm_repository() {
  echo "install-datadog: adding datadoghq.com helm repository"
  helm repo --kubeconfig openshift/kubeconfig add datadog https://helm.datadoghq.com &>/dev/null || true
  echo "install-datadog: updating helm repo"
  helm repo --kubeconfig openshift/kubeconfig update &>/dev/null || true
}

import_redhat_images() {
  local cluster_context="$1"

  echo "install-datadog: importing redhat registry images for datadog operator, agent, and cluster-agent"
  echo "    >- ${DD_OPERATOR_IMAGE_VERSION}"
#  echo "    >- ${DD_AGENT_IMAGE_VERSION}"
#  echo "    >- ${DD_CLUSTER_AGENT_IMAGE_VERSION}"
  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" import-image "${DD_OPERATOR_IMAGE_VERSION#registry.connect.redhat.com/}" --from="${DD_OPERATOR_IMAGE_VERSION}" --confirm &>/dev/null || {
    echo "install-datadog: failed to import $DD_OPERATOR_IMAGE_VERSION"
    exit 1
  }
  echo "install-datadog: successfully imported $DD_OPERATOR_IMAGE_VERSION"
#  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" import-image "${DD_AGENT_IMAGE_VERSION#registry.connect.redhat.com/}" --from="${DD_AGENT_IMAGE_VERSION}" --confirm &>/dev/null || {
#    echo "install-datadog: failed to import $DD_AGENT_IMAGE_VERSION"
#    exit 1
#  }
#  echo "install-datadog: successfully imported $DD_CLUSTER_AGENT_IMAGE_VERSION"
#  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" import-image "${DD_CLUSTER_AGENT_IMAGE_VERSION#registry.connect.redhat.com/}" --from="${DD_CLUSTER_AGENT_IMAGE_VERSION}" --confirm &>/dev/null || {
#    echo "install-datadog: failed to import $DD_CLUSTER_AGENT_IMAGE_VERSION"
#    exit 1
#  }
}

function create_namespace() {
  local cluster_context="$1"
  local namespace="$2"
  echo "install-datadog: creating namespace $namespace | context: $cluster_context"
  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" create namespace "$namespace" &>/dev/null || true
}

function create_secret() {
  local cluster_context="$1"
  local namespace="$2"
  local secret_name="$3"
  local key="$4"
  echo "install-datadog: creating $secret_name secret in namespace $namespace | context: $cluster_context"
  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" -n "$namespace" create secret generic "$secret_name" --from-literal="key=$key" &>/dev/null || true
}

function share_consul_secrets() {
    local cluster_context="$1"
    local namespace="$2"

    echo "install-datadog: sharing consul tls secrets with dd-agent | context: $cluster_context"
    openshift/oc --kubeconfig openshift/kubeconfig get secret --context "$cluster_context" consul-ca-cert -n "$namespace" -o json | \
      jq '.metadata.namespace = "datadog"' | openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" create -f - &>/dev/null || true
    openshift/oc --kubeconfig openshift/kubeconfig get secret --context "$cluster_context" consul-server-cert -n "$namespace" -o json | \
      jq '.metadata.namespace = "datadog"' | openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" create -f - &>/dev/null || true
}

function install_dd_operator() {
    local cluster_context="$1"
    local namespace="$2"

    echo "install-datadog: installing datadog-operator in $namespace | context: $cluster_context"
    helm install \
      datadog-operator \
      datadog/datadog-operator \
      --namespace "$namespace" \
      --set image.tag="$datadogOperatorVersion" \
      --set-json podAnnotations='{"consul.hashicorp.com/connect-inject": "false"}' \
      --set replicaCount=1 \
      --kubeconfig openshift/kubeconfig \
      --kube-context "$cluster_context" # &>/dev/null || true
}

function deploy_dd_agent() {
    local cluster_context="$1"
    local namespace="$2"
    export DC="$3"
    eval "$(cat .ddImages.env)"

    echo "install-datadog: deploying dd-agent ($DC) to cluster in namespace $namespace | context: $cluster_context"
    envsubst < datadog/datadog-intentions.yaml | openshift/oc --kubeconfig openshift/kubeconfig --namespace "$namespace" --context "$cluster_context" apply -f -
    envsubst < datadog/datadog-service-defaults.yaml | openshift/oc --kubeconfig openshift/kubeconfig --namespace "$namespace" --context "$cluster_context" apply -f -
    envsubst < datadog/datadog-agent.yaml | openshift/oc --kubeconfig openshift/kubeconfig --namespace "$namespace" --context "$cluster_context" apply -f -
}

## Using datadog operator to install DD => defaults to enable the admission controller
## if connectInject.enabled and connectInject.default=true, there'll be a conflict between
## the admission controller and the DD cluster-agent (if enabled and deployed), this
## patches the admission controller with "consul.hashicorp.com/service-ignore": "true" to
## tell consul that it should register the cluster-agent as a service, not the admission controller.
function update_admission_controller() {
    local cluster_context="$1"
    local namespace="$2"
    local ADMIN_CONTROLLER_SVC
    eval "$(cat .ddImages.env)"

    echo "install-datadog: waiting for admission controller service..."; sleep 10
    while [ -z "$ADMIN_CONTROLLER_SVC" ]; do
      ADMIN_CONTROLLER_SVC=$(openshift/oc --kubeconfig openshift/kubeconfig get service --context "$cluster_context" datadog-admission-controller -n "$namespace" -o json 2>&1)
      [ -z "$ADMIN_CONTROLLER_SVC" ] && sleep 1
    done
    echo "install-datadog: patching dd admin controller for connect service ignore in $namespace | context: $cluster_context"
    echo "$ADMIN_CONTROLLER_SVC" | jq '.metadata.labels += { "consul.hashicorp.com/service-ignore": "true" }' | \
       openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" apply -f - >/dev/null 2>&1 || true
}

if [ -z "$DATADOG_API_KEY" ]; then
  echo "    [ERROR] >- install-datadog: DATADOG_API_KEY not set, api key is required to run datadog."
  exit 1
fi

if [ -z "$DATADOG_APP_KEY" ]; then
  echo "    [ERROR] >- install-datadog: DATADOG_API_KEY not set, api key is required to run datadog."
  exit 1
fi

add_dd_helm_repository
i=1
for cluster_context in "${CLUSTER_CONTEXTS[@]}"; do
  # create_namespace "$cluster_context" "$DD_NS"
  create_secret "$cluster_context" "$DD_NS" datadog-secret "${DATADOG_API_KEY}"
  create_secret "$cluster_context" "$DD_NS" datadog-secret-app "${DATADOG_APP_KEY}"
  share_consul_secrets "$cluster_context" consul
  # import_redhat_images "$cluster_context"
  # install_dd_operator "$cluster_context" datadog
  deploy_dd_agent "$cluster_context" datadog "dc${i}"
  # update_admission_controller "$cluster_context" datadog
  i=$((i+1))
done

