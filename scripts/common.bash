#!/usr/bin/env bash


now(){
 printf '%s\n' "$(date '+%d/%m/%Y %H:%M:%S')";
}


## Podman image used to run coreos-installer from mac
coreos-installer() {
  podman run --privileged --rm -v "$PWD":/data -w /data quay.io/coreos/coreos-installer:release "$@"
}