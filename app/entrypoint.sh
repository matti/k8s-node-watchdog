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
  aws)

  ;;
  *)
    echo "unsupported provider: ${PROVIDER}"
    sleep 60
    exit 1
  ;;
esac

while true; do
  while true; do
    set +e
      nsenter -t 1 -m -u -i -n -- uptime
    set -e

    if ! kubectl get node >/dev/null; then
      echo "kube api not ok"
    else
      case "${PROVIDER}" in
        aws)
          # https://github.com/weaveworks/eksctl/issues/2363#issuecomment-830651744
          # and
          # Failed to validate kubelet flags" err="unknown 'kubernetes.io' or 'k8s.io' labels specified with --node-labels: [node-role.kubernetes.io/something]\n--node-labels in the 'kubernetes.io' namespace must begin with an allowed prefix (kubelet.kubernetes.io, node.kubernetes.io) or be in the specifically allowed set (beta.kubernetes.io/arch, beta.kubernetes.io/instance-type, beta.kubernetes.io/os, failure-domain.beta.kubernetes.io/region, failure-domain.beta.kubernetes.io/zone, kubernetes.io/arch, kubernetes.io/hostname, kubernetes.io/os, node.kubernetes.io/instance-type, topology.kubernetes.io/region, topology.kubernetes.io/zone)"

          set +e
            nodegroup=$(kubectl get node "${NODE_HOSTNAME}" --output=jsonpath='{.metadata.labels.eks\.amazonaws\.com\/nodegroup}')
          set -e

          if [ "$nodegroup" = "" ]; then
            echo "failed to read nodegroup"
            break
          fi

          kubectl label node "${NODE_HOSTNAME}" --overwrite=true "node-role.kubernetes.io/${nodegroup}=yes" || echo "node labeling failed"
        ;;
      esac
    fi

    break
  done

  sleep 10
done