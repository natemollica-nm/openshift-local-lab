#!/usr/bin/env bash

export ASSISTED_SERVICE_API="api.openshift.com" # Setting the Assisted Installer API endpoint
export OCP_RELEASE_IMAGE="$(openshift-install version | awk '/release image/ {print $3}')"

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

set -e

DEPLOYMENT_PAYLOAD=$(cat <<-EOF
{
  "kind": "Cluster",
  "name": "$OPENSHIFT_CLUSTER",
  "openshift_version": "$OPENSHIFT_VERSION",
  "ocp_release_image": "$OCP_RELEASE_IMAGE",
  "base_dns_domain": "$OPENSHIFT_DOMAIN",
  "hyperthreading": "all",
  "user_managed_networking": true,
  "vip_dhcp_allocation": false,
  "high_availability_mode": "None",
  "hosts": [],
  "ssh_public_key": "$SSH_KEY_LOCAL",
  "pull_secret": $PULL_SECRET,
  "network_type": "OVNKubernetes"
}
EOF
)

