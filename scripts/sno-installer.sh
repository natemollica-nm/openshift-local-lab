#!/usr/bin/env bash

source scripts/common.bash

test -f iso/rhcos-live.iso || {
  printf '%s\n' "sno-installer: iso/rhcos-live.iso not found! run: 'make rhcos-live-iso' and retry deployment"
  exit
}

export OPENSHIFT_VERSION="$1"
export SSH_KEY_LOCAL="$2"
export PULL_SECRET="'$(cat "$3")'"
export OPENSHIFT_HOSTNAME="$4"
export OPENSHIFT_CLUSTER="$5"
export OPENSHIFT_DOMAIN="$6"

export HOST_IP="$7"
export CIDR="$(printf '%s\n' "$HOST_IP" | cut -d'.' -f1-3).0/24"
export GATEWAY="$(printf '%s\n' "$HOST_IP" | cut -d'.' -f1-3).1"
export OPENSHIFT_IP="$(printf '%s\n' "$HOST_IP" | cut -d'.' -f1-3).40"

export INSTALL_TYPE="$8"

# Kernel ISO Networking Ref: https://docs.openshift.com/container-platform/4.15/installing/installing_bare_metal/installing-bare-metal-network-customizations.html#installation-user-infra-machines-routing-bonding_installing-bare-metal-network-customizations
KERNEL_ARGS="console=ttyS0 rd.neednet=1 ip=${OPENSHIFT_IP}::${GATEWAY}:255.255.255.0:${OPENSHIFT_HOSTNAME}.${OPENSHIFT_DOMAIN}:enp0s1:off::[4E:B5:D2:58:F8:56] nameserver=${HOST_IP} nameserver=192.168.0.1 nameserver=8.8.8.8"

printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n' \
  "    Single Node OpenShift (SNO) Installer (type: $INSTALL_TYPE) " \
  "    ----------------------------------------------------------- " \
  "    >- OpenShift Cluster:                 $OPENSHIFT_HOSTNAME" \
  "    >- OpenShift Domain:                  $OPENSHIFT_DOMAIN" \
  "    >- OpenShift Cluster CIDR:            $CIDR" \
  "    >- OpenShift DNS Server:              $HOST_IP" \
  "    >- OpenShift Cluster Gateway:         $GATEWAY" \
  "    >- OpenShift Node IP:                 $OPENSHIFT_IP" \
  "    >- OpenShift CoreOS Kernel Arguments: $KERNEL_ARGS"
# shellcheck disable=2162
read -p "review and approve the above settings (enter to continue, ctrl+c to cancel)"

# shellcheck disable=2162
updateOpenShiftConfigs() {
  envsubst <conf/agent-config.yaml >ocp/agent-config.yaml
  envsubst <conf/install-config.yaml >ocp/install-config.yaml
  read -p "$(now) sno-installer: review ocp/[install-config.yaml|agent-config.yaml] and update if necessary - (any key to continue | ctrl+c to cancel)"
}

buildOpenShiftInstallerImage() {
  local confirm

  podman build -f Containerfile -t openshift-install --build-arg VERSION="${OPENSHIFT_VERSION}"
  sleep 2
  confirm="$(podman run -it --rm openshift-install version 2>/dev/null | grep openshift-install | awk '{printf $2}' | tr -d '\n\r' | sed 's/^[[:space:]]*//')"
  if ! [[ "$confirm" =~ $OPENSHIFT_VERSION ]]; then
    printf '\n\n%s' "$(now) sno-installer: failed to start openshift-install agent iso installer image | '$confirm' != $OPENSHIFT_VERSION"
    exit 1
  fi
  printf '%s\n' "$(now) sno-installer: verified built and can run!!"
}

runOpenShiftAgentInstaller() {
  podman run --privileged --rm \
    -v "$(pwd)":/data \
    -v ./.installer_cache/image_cache:/root/.cache/agent/image_cache \
    -v ./.installer_cache/files_cache:/root/.cache/agent/files_cache \
    -w /data \
    openshift-install:latest --dir ocp/ agent create image
  test -f ocp/agent.aarch64.iso || {
    printf '%s\n' "$(now) sno-installer: failed to build ocp/agent.aarch64.iso"
    exit 1
  }
  printf '%s\n' "$(now) sno-installer: updating ocp/agent.aarch64.iso with kernel arguments | $KERNEL_ARGS"
  coreos-installer iso kargs modify -a "$KERNEL_ARGS" ocp/agent.aarch64.iso
  printf '%s\n' "$(now) sno-installer: successful! create UTM vm with ocp/agent.aarch64.iso"
}


runOpenShiftAgentInstallerIgnition() {
  local custom_install_to_disk_base64 INSTALL_TO_DISK_BASE64_CONTENT

  coreos-installer --version || {
    printf '%s\n' "sno-installer: failed to run coreos-installer alias function, exiting"
    exit 1
  }

  printf '%s\n' "$(now) sno-installer: generating single-node-ignition-config => ocp/bootstrap-in-place-for-live-iso.ign"
  openshift-install --dir=ocp create single-node-ignition-config


  INSTALL_TO_DISK_BASE64_CONTENT="$(jq -r '.storage.files[] | select(.path=="/usr/local/bin/install-to-disk.sh")' < ocp/bootstrap-in-place-for-live-iso.ign | jq -r .contents.source | sed 's/data:text\/plain;charset=utf-8;base64,//')"
  echo "${INSTALL_TO_DISK_BASE64_CONTENT}" | base64 -d > scripts/install-to-disk.sh
  printf '%s\n' "$(now) sno-installer: copying ocp/bootstrap-in-place-for-live-iso.ign => iso.ign"
  cp ocp/bootstrap-in-place-for-live-iso.ign iso.ign
  # shellcheck disable=2002
  custom_install_to_disk_base64=$(cat scripts/install-to-disk-customized.sh | base64 -b0)

  printf '%s\n' "$(now) sno-installer: updating base64 install-to-disk script with scripts/install-to-disk-customized.sh"
  sed -i '' "s/${INSTALL_TO_DISK_BASE64_CONTENT}/${custom_install_to_disk_base64}/g" iso.ign

  printf '%s\n' "$(now) sno-installer: embedding iso.ign with iso/rhcos-live.iso"
  coreos-installer iso ignition embed -fi iso.ign iso/rhcos-live.iso

  printf '%s\n' "$(now) sno-installer: updating rhcos-live.iso with kernel arguments | $KERNEL_ARGS"
  coreos-installer iso kargs modify -a "$KERNEL_ARGS" iso/rhcos-live.iso
  printf '%s\n' "$(now) sno-installer: coreos installer pre-installation configuration complete! create UTM vm with iso/rhcos-live.iso"
}



printf '%s\n' "$(now) sno-installer: copying conf/agent-config.yaml and conf/install-config.yaml => ocp/"
updateOpenShiftConfigs

if [ "$INSTALL_TYPE" = agent ]; then
  printf '%s\n' "$(now) sno-installer: building local openshift-install podman container for agent-installer iso generation"
  buildOpenShiftInstallerImage
  printf '%s\n' "$(now) sno-installer: running openshift-install --dir ocp/ agent create image => ocp/agent.aarch64.iso"
  runOpenShiftAgentInstaller
elif [ "$INSTALL_TYPE" = ign ]; then
  printf '%s\n' "$(now) sno-installer: running coreos-installer iso ignition embed -fi ocp/bootstrap-in-place-for-live-iso.ign iso/rhcos-live.iso"
  runOpenShiftAgentInstallerIgnition
else
  printf '%s\n' "$(now) sno-installer: invalid parameter! | $INSTALL_TYPE"
  exit
fi

printf '\n%s\n' "    *===> pre-installation agent configuration complete for $INSTALL_TYPE installation type!"
