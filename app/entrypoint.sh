#!/usr/bin/env bash
set -euo pipefail

OS_RELEASE_ID=$(nsenter -t 1 -m -u -i -n -- awk -F= '$1=="ID" { print $2 ;}' /etc/os-release)
if nsenter -t 1 -m -u -i -n -- test -f /etc/google_instance_id; then
  PROVIDER="gke"
elif [ "$OS_RELEASE_ID"="amzn" ]; then
  PROVIDER="aws"
else
  PROVIDER="unknown"
fi
NODE_HOSTNAME=$(nsenter -t 1 -m -u -i -n -- hostname)

echo "PROVIDER=$PROVIDER"
echo "OS_RELEASE_ID=$OS_RELEASE_ID"
echo "NODE_HOSTNAME=$NODE_HOSTNAME"

case "$PROVIDER" in
  gke)
    case "$OS_RELEASE_ID" in
      ubuntu)
        if ! command -v python; then
          echo "fixing node-problem-detector by installing the missing python"
          (
            exec nsenter -t 1 -m -u -i -n -- apt-get update
          ) 2>&1 >/tmp/apt-get-update.log
          echo "apt-get update ok"

          (
            exec nsenter -t 1 -m -u -i -n -- apt-get install -y python
          ) 2>&1 >/tmp/apt-get-install-python.log
          echo "apt-get install -y python ok"
        fi
      ;;
    esac
  ;;
esac

while true; do
  set +e
    nsenter -t 1 -m -u -i -n -- uptime
  set -e

  if ! kubectl get node >/dev/null; then
    echo "kube api not ok"
  fi

  sleep 10
done