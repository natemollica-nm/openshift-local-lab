#!/usr/bin/env bash

export HOST_IP="$1"
export OPENSHIFT_DOMAIN="$2"

export OPENSHIFT_IP="$(echo "$HOST_IP" | cut -d'.' -f1-3).40"

printf '%s\n' "verifying /etc/resolver/$OPENSHIFT_DOMAIN nameserver entry"
if ! test -f "/etc/resolver/$OPENSHIFT_DOMAIN"; then
  printf '%s\n' "setting /etc/resolver/$OPENSHIFT_DOMAIN with 'nameserver 127.0.0.1'"
  echo "nameserver 127.0.0.1" | sudo tee "/etc/resolver/$OPENSHIFT_DOMAIN" >/dev/null
fi


printf '%s\n' "verifying /etc/hosts has $OPENSHIFT_DOMAIN entry"
HOST_FILE_UPDATED=$(grep "$OPENSHIFT_DOMAIN" /etc/hosts)
if [[ -z "$HOST_FILE_UPDATED" ]];
  then   # If the grep returns nothing...
    printf '%s\n' "updating /etc/hosts with '$OPENSHIFT_IP     $OPENSHIFT_DOMAIN'"
    echo "$OPENSHIFT_IP    $OPENSHIFT_DOMAIN" | sudo tee -a /etc/hosts >/dev/null
    grep "$OPENSHIFT_DOMAIN" /etc/hosts
  else
    printf '%s\n' "$OPENSHIFT_DOMAIN already exists | $(grep "$OPENSHIFT_DOMAIN" /etc/hosts)"
    printf '\n%s\n' "  => Reapply /etc/hosts file $OPENSHIFT_DOMAIN entry? (y/N)"
    # shellcheck disable=2162
    read response < /dev/tty
    case "$response" in
      [Yy]* )
          printf '%s\n' "hosts-file: backing up /etc/hosts file => /etc/hosts.bak"
          if test -f /etc/hosts.bak; then
            sudo rm /etc/hosts.bak && sudo cp /etc/hosts /etc/hosts.bak
          else
            sudo cp /etc/hosts /etc/hosts.bak
          fi
          printf '%s\n' "hosts-file: removing previous $OPENSHIFT_DOMAIN entry from /etc/hosts"
          sudo sed -i '' "/$OPENSHIFT_DOMAIN/d" /etc/hosts

          printf '%s\n' "updating /etc/hosts with '$OPENSHIFT_IP     $OPENSHIFT_DOMAIN'"
          echo "$OPENSHIFT_IP    $OPENSHIFT_DOMAIN" | sudo tee -a /etc/hosts >/dev/null
          grep "$OPENSHIFT_DOMAIN" /etc/hosts
          ;;
      * )
          printf '%s\n' "hosts-file: skipping /etc/hosts file update (already present)..."
          ;;
    esac
fi

