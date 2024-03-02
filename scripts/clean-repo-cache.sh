#!/usr/bin/env bash

function enableHelmRepo {
  echo "helm: clearing helm repository cache from $HOME/Library/Caches/helm/repository"
  rm -rf "${HOME}"/Library/Caches/helm/repository/* || true
  sleep 2
  echo "helm: adding https://helm.releases.hashicorp.com and updating"
  helm repo --kubeconfig .secrets/kubeconfig-noingress add hashicorp https://helm.releases.hashicorp.com &>/dev/null
  helm repo --kubeconfig .secrets/kubeconfig-noingress update &>/dev/null
}

enableHelmRepo