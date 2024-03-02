#!/usr/bin/env bash

set -e

source scripts/common.bash

export OPENSHIFT_HOSTNAME="$1"
export OPENSHIFT_DOMAIN="$2"
export HOST_IP="$3"

# shellcheck disable=2155
export CIDR="$(echo "$HOST_IP" | cut -d'.' -f1-3).0/24"
# shellcheck disable=2155
export OPENSHIFT_IP="$(echo "$HOST_IP" | cut -d'.' -f1-3).40"
# shellcheck disable=2155
export PTR="$(echo "$OPENSHIFT_IP" | awk -F '.' '{print $4"."$3"."$2"."$1}')"

if [ -z "$HOST_IP" ]; then
  echo "$(now) dnsmasq: null or invalid localhost IP! verify Makefile IP variable is pointing to valid interface (i.e., en0, eth0, etc)"
  exit 1
fi

printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$(now) dnsmasq: updating dnsmasq.conf" \
    "  >- domain: $OPENSHIFT_DOMAIN"  \
    "  >- hostname: $OPENSHIFT_HOSTNAME" \
    "  >- localhost ip: $HOST_IP" \
    "  >- openshift-node ip: $OPENSHIFT_IP" \
    "  >- openshift CIDR: $CIDR"
printf '\n'
read -p 'dnsmasq: confirm the above setting configurations - (any key to continue | ctrl+c to cancel)'
envsubst < conf/dnsmasq-template.conf > dnsmasq.conf
printf '%s\n' "$(now) dnsmasq: dnsmasq.conf update complete!"