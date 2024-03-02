#!/usr/bin/env bash

set -e

CLUSTER_CONTEXTS=("$CLUSTER1_CONTEXT")

function uninstall_datadog() {
  local cluster_context="$1"
  local namespace="$2"
  export DC="$3"

  echo "uninstall-datadog: deleting datadog resources from $cluster_context"
  envsubst < datadog/datadog-intentions.yaml | openshift/oc --kubeconfig openshift/kubeconfig --namespace "$namespace" --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < datadog/datadog-service-defaults.yaml | openshift/oc --kubeconfig openshift/kubeconfig --namespace "$namespace" --context "$cluster_context" delete -f - &>/dev/null || true
  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" --namespace "$namespace" delete -f datadog/datadog-agent.yaml &>/dev/null || true
  echo "uninstall-datadog: uninstalling datadog-operator via helm from $cluster_context"
  helm uninstall --kubeconfig openshift/kubeconfig --kube-context "$cluster_context" --namespace "$namespace" datadog-operator &>/dev/null || true
}

i=1
for cluster_context in "${CLUSTER_CONTEXTS[@]}"; do
  uninstall_datadog "$cluster_context" datadog "dc${i}"
  i=$((i+1))
  echo "uninstall-datadog: deleting datadog namespace"
  openshift/oc --kubeconfig openshift/kubeconfig --context "$cluster_context" delete namespace datadog &>/dev/null || true
done
