#!/usr/bin/env bash

source scripts/common.bash

downloadISO() {
  local rhcos_url arch
  arch=aarch64

  # ISO: download rhcos-live.aarch64.iso
  rhcos_url="$(openshift-install coreos print-stream-json | grep location | grep $arch | grep iso | cut -d\" -f4)"
  printf '%s\n' "$(now) rhcos-live-iso: downloading iso/rhcos-live.iso | $rhcos_url"
  curl -sL "$rhcos_url" -o iso/rhcos-live.iso
  test -f iso/rhcos-live.iso
}

if test -f iso/rhcos-live.iso; then
  printf '%s\n' "$(now) rhcos-live-iso: previous iso/rhcos-live.iso found"
  printf '\n%s\n' "Download an updated copy? (y/N)"
  # shellcheck disable=2162
  read -r response </dev/tty
  case "$response" in
  [Yy]*)
    printf '%s\n' "rhcos-live-iso: deleting iso/rhcos-live.iso"
    rm -v iso/rhcos-live.iso
    if ! downloadISO; then
      printf '%s\n' "$(now) rhcos-live-iso: failed to download iso/rhcos-live.iso, exiting..."
      exit 1
    fi
    ;;
  *)
    printf '%s\n' "$(now) rhcos-live-iso: skipping rhcos-live.iso download..."
    ;;
  esac
else
  if ! downloadISO; then
    printf '%s\n' "$(now) rhcos-live-iso: failed to download iso/rhcos-live.iso, exiting..."
    exit 1
  fi
fi

printf '%s\n' "$(now) rhcos-live-iso: rhcos-live.iso download successful!"
printf '\n%s\n' "   *===> deploy test UTM Linux VM using rhcos-live.iso and update the VMs NIC Mac Address to 4E:B5:D2:58:F8:56"