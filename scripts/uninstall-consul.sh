#!/usr/bin/env bash

set -e

CTX="$1"
FORCE="${2:-false}"

function delete_consul_crds() {
  local cluster_context="$1"
  export PEER="$2"
  export PARTITION=default
  if [ "$cluster_context" == "$CLUSTER2_CONTEXT" ]; then
    export PARTITION=ap1
  fi
  echo "uninstall-consul: removing consul crds from $cluster_context | KUBECONFIG=$KUBECONFIG"
  envsubst < "crds/mesh.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/proxy-defaults.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/intentions.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/exported-services.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/static-server-service-resolver.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/static-server-service-defaults.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/fake-service-resolver.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
  envsubst < "crds/fake-service-defaults.yaml" | oc --context "$cluster_context" delete -f - &>/dev/null || true
}

function delete_kube_services() {
  local cluster_context="$1"
  export PEER="$2"
  export PARTITION="$3"
  
  echo "uninstall-consul: uninstalling kube services from $cluster_context"
  envsubst < crds/static-server-template.yaml | oc delete --context "$cluster_context" -f - &>/dev/null || true
  envsubst < crds/static-client-template.yaml | oc delete --context "$cluster_context" -f - &>/dev/null || true
  envsubst < crds/frontend-service-template.yaml | oc delete --context "$cluster_context" -f - &>/dev/null || true
  envsubst < crds/backend-service-template.yaml | oc delete --context "$cluster_context" -f - &>/dev/null || true
}

function force_uninstall() {
  echo "running forced namespace cleanup on consul resources | $CTX"
  read -r -p "run knsk.sh --delete-all --force? (y/n): " ans
  case $ans in
    y|yes)
      echo "force uninstalling consul resources from $CTX" && \
      oc config use-context "$CTX"
      scripts/knsk.sh --delete-all --force && \
      echo "force uninstallation complete!"
    ;;
    n|no)
      echo "cancelled force-uninstallation"
    ;;
  esac
}


if [ "$FORCE" = true ]; then
  force_uninstall
else
  echo "uninstall-consul: running helm uninstall on consul in $CONSUL_NS namespace"
  helm uninstall consul --namespace "$CONSUL_NS" || {
    echo "uninstall-consul: helm uninstall failed! Attempting consul-k8s cli uninstall | $CTX"
    consul-k8s uninstall -context "$CTX" -namespace "$CONSUL_NS" -auto-approve=true -wipe-data=true 2>&1 || true
  }
  for ns in $CONSUL_NS; do
    echo "uninstall-consul: deleting namespace $ns | $CTX"
    oc --context "$CTX" delete namespace "$ns" &>/dev/null || true
  done
fi
