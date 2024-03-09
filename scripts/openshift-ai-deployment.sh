#!/usr/bin/env bash

set -e

eval "$(cat .env)"

export CLUSTER_ID OCP_RELEASE_IMAGE CIDR GATEWAY OPENSHIFT_IP PULL_SECRET

export ASSISTED_SERVICE_API="api.openshift.com" # Setting the Assisted Installer API endpoint

export OPENSHIFT_VERSION="$1"
export SSH_KEY_LOCAL="$2"
PULL_SECRET="'$(cat "$3")'"
export OPENSHIFT_HOSTNAME="$4"
export OPENSHIFT_CLUSTER="$5"
export OPENSHIFT_DOMAIN="$6"
export HOST_IP="$7"

DATA=$(mktemp)
SNO_NIC="enp0s1"
SNO_NIC_MAC_ADDRESS="4E:B5:D2:58:F8:56"
CIDR="$(printf '%s\n' "$HOST_IP" | cut -d'.' -f1-3).0/24"
GATEWAY="$(printf '%s\n' "$HOST_IP" | cut -d'.' -f1-3).1"
OPENSHIFT_IP="$(printf '%s\n' "$HOST_IP" | cut -d'.' -f1-3).40"
OCP_RELEASE_IMAGE="$(openshift-install version | awk '/release image/ {print $3}')"

printf '%s\n' "ai-sno-installer: configuring deployment payload | assisted-installer-deployment.json"
envsubst < conf/assisted-installer-deployment-template.json > ocp/assisted-installer-deployment.json

cat ocp/assisted-installer-deployment.json
read -p -r "ai-sno-installer: confirm ai installer deployment settings (any key to continue | ctrl+c to cancel)"

printf '%s\n' "ai-sno-installer: obtaining cluster id from $ASSISTED_SERVICE_API | $TOKEN"
CLUSTER_ID=$(curl -s -X POST "https://$ASSISTED_SERVICE_API/api/assisted-install/v1/clusters" \
  -d @./deployment.json \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.id' )
CLUSTER_ID="$( sed -e 's/^"//' -e 's/"$//' <<<"$CLUSTER_ID")"

if [ -z "$CLUSTER_ID" ]; then
  printf '%s\n' "ai-sno-installer: failed to obtain as-installer cluster id"
  exit 1
fi

printf '%s\n' "ai-sno-installer: configuring sno cluster static networking via conf/nmstate.yaml"
jq --null-input \
  --arg SSH_KEY_LOCAL "$SSH_KEY_LOCAL" \
  --arg NMSTATE_YAML "$(cat conf/nmstate.yaml)" \
  --arg MAC_ADDRESS "$SNO_NIC_MAC_ADDRESS" --arg NIC "$SNO_NIC" \
'{
  "ssh_public_key": $SSH_KEY_LOCAL,
  "image_type": "full-iso",
  "static_network_config": [
    {
      "network_yaml": $NMSTATE_YAML,
      "mac_interface_map": [{"mac_address": "$MAC_ADDRESS", "logical_nic_name": "$NIC"}]
    }
  ]
}' >> "$DATA"

cat "$DATA"
read -p -r "ai-sno-installer: confirm NMSTATE settings (any key to continue | ctrl+c to cancel)"

printf '%s\n' "ai-sno-installer: generating ai installer iso from https://$ASSISTED_SERVICE_API/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image"
curl -X POST \
"https://$ASSISTED_SERVICE_API/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d @"$DATA"

printf '%s\n%s\n%s\n' "ai-sno-installer: downloading ai installer iso:" \
  "    >- download url: http://$ASSISTED_SERVICE_API/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
  "    >- location:     iso/discovery-image-$OPENSHIFT_CLUSTER.iso"
curl -L \
  "http://$ASSISTED_SERVICE_API/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
  -o iso/discovery-image-"$OPENSHIFT_CLUSTER".iso \
  -H "Authorization: Bearer $TOKEN"