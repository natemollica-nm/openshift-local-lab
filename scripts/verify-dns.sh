#!/usr/bin/env bash

source scripts/common.bash

set -e

export OPENSHIFT_CLUSTER="$1"
export OPENSHIFT_HOSTNAME="$2"
export OPENSHIFT_DOMAIN="$3"

RECORDS=(api api-int fake-service.apps consul-openshift-console.apps bootstrap)

printf '%s\n' "$(now) dnsmasq: starting openshift dns verification"
for record in "${RECORDS[@]}"; do
  printf '%s' "$(now) dnsmasq: verifying dns resolution for "
  if ! dig +noall +answer @127.0.0.1 "$record"."$OPENSHIFT_CLUSTER"."$OPENSHIFT_DOMAIN"; then
    printf '\n%s\n' "$(now) dnsmasq: dns verification failed | record: $record.$OPENSHIFT_CLUSTER.$OPENSHIFT_DOMAIN"
    exit 1
  fi
done
printf '\n%s\n' "   *===> openshift dns resolution verified!"