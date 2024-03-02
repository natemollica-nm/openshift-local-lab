#!/bin/bash

set -e

ACTION="${1:-create}"

eval "$(cat .env)"

apply_templates() {
  local cluster_context="$1"
  local action="$2"

  echo "fake-services: running oc ${action} for frontend | backend services, sa, deploy, service-intentions, service-defaults, and service-resolvers"
  envsubst < fake/frontend-service-template.yaml | oc "${action}" --context "$cluster_context" -f - &>/dev/null || true
  envsubst < fake/backend-service-template.yaml | oc "${action}" --context "$cluster_context" -f - &>/dev/null || true
  envsubst < fake/intentions.yaml | oc "${action}" --context "$cluster_context" -f - &>/dev/null || true
  envsubst < fake/service-defaults.yaml | oc "${action}" --context "$cluster_context" -f - &>/dev/null || true
  envsubst < fake/service-resolver.yaml | oc "${action}" --context "$cluster_context" -f - &>/dev/null || true
}

if [ "${ACTION}" = delete ]; then
  apply_templates "$CLUSTER1_CONTEXT" delete
  exit 0
fi
apply_templates "$CLUSTER1_CONTEXT" apply
