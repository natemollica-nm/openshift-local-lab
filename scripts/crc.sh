#!/usr/bin/env bash

function defaults() {
  CRC_API="https://api.crc.testing:6443"
  CRC_CONSOLE="https://console-openshift-console.apps-crc.testing"

  CPUs=4
  MEM=9216
  PULL_SECRET_FILE="$(readlink -f openshift/pull-secret.txt)"
  CRC_USER=developer
  PASS=developer
}


function usage() {
  defaults
  cat <<-EOF
############################
OpenShift Local Cluster Tool
############################

  Requires:    crc
  Platform(s): mac osx

Usage:
    Full:
      $(basename "$0") {setup|start|login|credentials} [parameters]

Parameters:
  -u  | --username:    crc api login username            (Default: "$CRC_USER")
  -p  | --password:    crc api login password            (Default: "$PASS")
  -ps | --pull-secret: crc cluster pull-secret file path (Default: "$PULL_SECRET_FILE")
EOF
}

function start() {
  local ps="$1"
  local cpu="$2"
  local mem="$3"

  echo "openshift-local: disabling cluster monitoring (too much memory usage ~14336 Gi)"
  crc config set enable-cluster-monitoring false
  echo "openshift-local: starting crc with pull-secret $ps | memory: $mem | cpu: $cpu"
  crc start --pull-secret-file="$ps" --memory "$mem" --cpus "$cpu"
}

function crc_password() {
  printf '%s\n' "$(crc start 2>/dev/null | grep 'Password:' | head -n1 | awk '{print $2}')"
}

function login() {
  local user="$1"
  local pw="$2"

  echo "openshift-local: logging into local openshift cluster | un: $user"
  eval "$(crc oc-env)"
  oc login -u "$user" "$CRC_API" -p "$pw"
}

function flags() {
  local PARAM VALUE

  while [ "$#" -gt 0 ]; do
    PARAM="$1"
    VALUE="$2"

    case $PARAM in
      -u|--username)
        CRC_USER="${VALUE}"; shift;
        ;;
      -p|--password)
        PASS="${VALUE}"; shift;
        ;;
      -cpu|--cpus)
        CPUs="${VALUE}"; shift;
        ;;
      -mem|--memory)
        MEM="${VALUE}"; shift;
        ;;
      -ps|--pull-secret)
        PULL_SECRET_FILE="${VALUE}"; shift;
        ;;
      (--) shift; break;;
      -*)
        echo "Unknown flag parameter ${PARAM}"
        usage
        exit 1
        ;;
      (*) break;;
    esac
    shift
  done
}


function main() {
  local SUBCOMMAND
  defaults
  # Main script logic for handling subcommands
  if [ "$#" -lt 1 ]; then
      usage
      exit 1
  fi

  SUBCOMMAND=$1
  shift # Remove the first argument, which is the subcommand

  flags "$@"
  case "$SUBCOMMAND" in
      setup)
          crc setup
          ;;
      start)
          start "$PULL_SECRET_FILE" "$CPUs" "$MEM"
          ;;
      login)
          login "$CRC_USER" "$PASS"
          ;;
      credentials)
          printf '\n%s\n%s\n%s' "CRC Console: $CRC_CONSOLE" "Username: kubeadmin" "Password: $(crc_password)"
          ;;
      -h|-\?|--help) usage; exit;
        ;;
      -*|*)
        echo "Unknown parameter ${SUBCOMMAND}";
        usage;
        exit 1
        ;;
  esac
}

main "$@"
