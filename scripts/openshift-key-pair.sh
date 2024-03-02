#!/usr/bin/env bash

set -e

openshift_key=aws-ssh-keys/openshift-key.pem
openshift_public_key=aws-ssh-keys/openshift-key.pem.pub

packer_key_copy=packer/configs/openshift-key.pem
packer_pub_key_copy=packer/configs/openshift-key.pem.pub

# if no openshift keys present, generate using ssh-keygen
if { ! test -f "$openshift_key"; } && { ! test -f "$openshift_public_key"; }; then
  ssh-keygen -t ed25519 -N '' -f aws-ssh-keys/openshift-key

  # remove any previously generated ssh keys to make room
  # for latest keys
  rm "$packer_key_copy" "$packer_pub_key_copy"
else
  echo "openshift-ssh: openshift-key.pem and openshift-key.pem.pub already generated, skipping..."
fi

# if no keys found for packer ami, copy recently generated (or previously generated)
# keys
if { ! test -f "$packer_key_copy"; } && { ! test -f "$packer_pub_key_copy"; }; then
  cp "$openshift_key" "$packer_key_copy"
  cp "$openshift_public_key" "$packer_pub_key_copy"
else
  echo "openshift-ssh: openshift-key.pem and openshift-key.pem.pub already staged for packer build, skipping..."
fi
echo "***** openshift ssh key-pair generation complete!"
