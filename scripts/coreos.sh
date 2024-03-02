#!/usr/bin/env bash

set -eou pipefail

# Main script logic for handling download prerequisite behavior
SKIP_INSTALL_PREREQs=0
CLEAN=0
if [ "$#" -ge 1 ]; then
  SUBCOMMAND=$1
  case "$SUBCOMMAND" in
      skip)
          SKIP_INSTALL_PREREQs=1
          ;;
      clean)
          CLEAN=1
          ;;
      -*|*)
        echo "Unknown parameter ${SUBCOMMAND}";
        echo "Usage $(basename "$0") {skip|clean}"
        exit 1
        ;;
  esac
fi

if [ $CLEAN = 1 ]; then
  echo "openshift-local: cleaning up..."
  rm -rf install/*
  rm -rf install/.openshift_install.log
  rm -rf install/.openshift_install_state.json
  podman machine stop
  podman machine rm podman-machine-default
  exit
fi

ARCH=aarch64
ISO_URL="$(openshift-install coreos print-stream-json | grep location | grep $ARCH | grep iso | cut -d\" -f4)" # ISO: rhcos-414.92.202401110948-0-live.x86_64.iso
export CLUSTER_NAME=consul-sno-cluster
export DNS_HOSTED_ZONE=openshift.localhost
# shellcheck disable=SC2155
export PULL_SECRET="'$(cat "$HOME"/HashiCorp/consul-aws-openshift/openshift/pull-secret.txt)'"
# shellcheck disable=SC2155
export SSH_KEY_LOCAL="$(cat "$HOME"/.ssh/id_rsa.pub)"
# shellcheck disable=SC2155
export BOOTSTRAP_IGN=install/bootstrap-in-place-for-live-iso.ign
export RHCOS_ISO=rhcos-live.iso

openshift_install_config="$(cat <<-EOF
apiVersion: v1
metadata:
  name: "\$CLUSTER_NAME"
platform:
  none: {}
baseDomain: "\$DNS_HOSTED_ZONE"
compute:
  - name: worker
    replicas: 0
controlPlane:
  name: master
  replicas: 1
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  machineNetwork:
    - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
    - 172.30.0.0/16
bootstrapInPlace:
  installationDisk: "\$INSTALLATION_DISK"
pullSecret: "\$PULL_SECRET"
sshKey: "\$SSH_KEY_LOCAL"
EOF
)"

test -f install-config.yaml || { echo "$openshift_install_config" > install-config.yaml; }
test -d install || { mkdir -p install; }

if [ "$SKIP_INSTALL_PREREQs" != 1 ]; then
  rm -rf install/*
  rm -rf install/.openshift_install.log
  rm -rf install/.openshift_install_state.json
  if ! podman machine list; then
    podman machine init
    podman machine set --rootful
    podman machine start
  fi
  if test -f rhcos-live.iso; then
    echo "openshift-local: removing previous rhcos-live.iso"
    rm rhcos-live.iso
  fi
  echo "openshift-local: downloading rhcos-live.iso | $ISO_URL"
  curl -sL "$ISO_URL" -o rhcos-live.iso
  test -f rhcos-live.iso || { echo "openshift-local: failed to download rhcos-live.iso, exiting..."; exit 1; }

  echo "openshift-local: copying install-config.yaml to install/"
  envsubst < install-config.yaml | tee install/install-config.yaml
  test -f install/install-config.yaml || { echo "openshift-local: failed to create install/install-config.yaml, exiting..."; exit 1; }

  echo "openshift-local: running openshift-install --dir install/ create single-node-ignition-config"
  openshift-install --dir=install/ create single-node-ignition-config
fi

echo "Please enter your sudo password for podman coreos container run:"
# shellcheck disable=SC2162
read -s sudo_password

#shellcheck disable=SC2276,2016
alias coreos-installer='sudo -S podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release'

echo "openshift-local: running coreos-installer iso ignition embed -fi $BOOTSTRAP_IGN $RHCOS_ISO"
echo "$sudo_password" | sudo -S podman run --privileged --pull always --rm -v /dev:/dev -v /run/udev:/run/udev -v "$(pwd)":/data -w /data quay.io/coreos/coreos-installer:release iso ignition embed -fi "$BOOTSTRAP_IGN" "$RHCOS_ISO"

echo "openshift-local: monitoring openshift-install installation"
openshift-install --dir=install/ wait-for install-complete