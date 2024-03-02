#!/bin/bash

set -eo pipefail

source scripts/common.bash

export OPENSHIFT_VERSION="$1"
export ARCH OS CLI_URL INSTALLER_URL CLI_URL CCOTL_URL EXECUTABLE_DIR

ARCH=aarch64
OS=$( [[ "$(uname | tr '[:upper:]' '[:lower:]' )" =~ darwin ]] && echo mac || echo linux )
EXECUTABLE_DIR=/usr/local/bin

if [ -z "$OPENSHIFT_VERSION" ]; then
  OPENSHIFT_VERSION="${OPENSHIFT_VERSION:=latest}"
fi

CLI_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"${OPENSHIFT_VERSION}"/openshift-client-"${OS}".tar.gz
INSTALLER_URL=https://mirror.openshift.com/pub/openshift-v4/"${ARCH}"/clients/ocp/"${OPENSHIFT_VERSION}"/openshift-install-"${OS}".tar.gz

install_oc() {
  echo "$(now) openshift-tools: Downloading openshift-cli | $CLI_URL"
  wget --quiet "${CLI_URL}" 1>/dev/null
  echo "$(now) openshift-tools: Un-archiving openshift-cli tar.gz"
  sudo tar -xf openshift-client-"${OS}".tar.gz -C "$EXECUTABLE_DIR"/
  sudo chmod a+x "$EXECUTABLE_DIR"/oc
  rm -f openshift-client-"${OS}".tar.gz
}

download_openshift_installer() {
  echo "$(now) openshift-tools: Downloading openshift-installer | $INSTALLER_URL"
  wget --quiet "${INSTALLER_URL}" 1>/dev/null
  echo "$(now) openshift-tools: Un-archiving openshift-installer tar.gz"
  sudo tar -xf openshift-install-"${OS}".tar.gz -C "$EXECUTABLE_DIR"/
  sudo chmod a+x "$EXECUTABLE_DIR"/openshift-install
  rm -f "$EXECUTABLE_DIR"/README.md >/dev/null 2>&1 || true
  rm -f "$EXECUTABLE_DIR"/LICENSE >/dev/null 2>&1 || true
  rm -f openshift-install-"${OS}".tar.gz >/dev/null 2>&1 || true
}

echo "$(now) Installing openshift-install and oc tools | version: $OPENSHIFT_VERSION"
for binary in \
  "$EXECUTABLE_DIR"/oc \
  "$EXECUTABLE_DIR"/kubectl \
  "$EXECUTABLE_DIR"/openshift-install \
  ; do
! test -f "$binary" || {
  echo "$(now) openshift-tools: removing previously installed binary | $binary"
  sudo rm "$binary"
}
done

echo "$(now) Starting openshift-cli installation | version: $OPENSHIFT_VERSION"
install_oc
command -v "$EXECUTABLE_DIR"/oc >/dev/null 2>&1 || {
  echo "$(now) openshift-cli: failed to install oc, exiting..."
  exit 1
}
command -v "$EXECUTABLE_DIR"/kubectl >/dev/null 2>&1 || {
  echo "$(now) openshift-cli: failed to install kubectl, exiting..."
  exit 1
}

echo "$(now) Starting openshift-install binary installation | version: $OPENSHIFT_VERSION"
download_openshift_installer
command -v "$EXECUTABLE_DIR"/openshift-install >/dev/null 2>&1 || {
  echo "$(now) openshift-install: failed to install, exiting..."
  exit 1
}

echo "$(now) OpenShift CLI and Installer Package installation complete!"
openshift-install version