#!/usr/bin/env bash
set -eEuo pipefail

_output() {
  echo ""
  echo "++ $*"
}

echo "start;$(date);$(uptime)" >> /k8s-node-watchdog/log

OS_RELEASE_ID=$(nsenter -t 1 -m -u -i -n -- awk -F= '$1=="ID" { print $2 ;}' /etc/os-release)
if nsenter -t 1 -m -u -i -n -- test -f /etc/google_instance_id; then
  PROVIDER="gke"
elif [[ "$OS_RELEASE_ID" == '"amzn"' ]]; then
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
          ) >/tmp/apt-get-update.log 2>&1
          echo "apt-get update ok"

          (
            exec nsenter -t 1 -m -u -i -n -- apt-get install -y python
          ) >/tmp/apt-get-install-python.log 2>&1
          echo "apt-get install -y python ok"
        fi
      ;;
    esac
  ;;
  aws)
    echo "no startup tasks for aws"
  ;;
  unknown)
    echo "unsupported provider"
    sleep 60
    exit 1
  ;;
esac

while true; do
  while true; do
    _output "nsenter uptime ..."
    if ! nsenter -t 1 -m -u -i -n -- uptime
    then
      _output "nsenter failed to uptime, strange"
    fi

    _output "kubectl get node ..."
    if ! kubectl get node >/dev/null
    then
      _output "failed, will try again"
      break
    fi

    _output "running"
    case "${PROVIDER}" in
      aws)
        # https://github.com/weaveworks/eksctl/issues/2363#issuecomment-830651744
        # and
        # Failed to validate kubelet flags" err="unknown 'kubernetes.io' or 'k8s.io' labels specified with --node-labels: [node-role.kubernetes.io/something]\n--node-labels in the 'kubernetes.io' namespace must begin with an allowed prefix (kubelet.kubernetes.io, node.kubernetes.io) or be in the specifically allowed set (beta.kubernetes.io/arch, beta.kubernetes.io/instance-type, beta.kubernetes.io/os, failure-domain.beta.kubernetes.io/region, failure-domain.beta.kubernetes.io/zone, kubernetes.io/arch, kubernetes.io/hostname, kubernetes.io/os, node.kubernetes.io/instance-type, topology.kubernetes.io/region, topology.kubernetes.io/zone)"

        _output "get this node ..."
        nodegroup=$(kubectl get node "${NODE_HOSTNAME}" --output=jsonpath='{.metadata.labels.eks\.amazonaws\.com\/nodegroup}' || true)

        if [ "$nodegroup" = "" ]; then
          _output "nodegroup not found, will try again"
          break
        fi

        _output "labeling node ..."
        kubectl label node "${NODE_HOSTNAME}" --overwrite=true "node-role.kubernetes.io/${nodegroup}=yes" || _output "node labeling failed"

        _output "annotating codedns to safe-to-evict ..."
        kubectl annotate pod --overwrite=true -n kube-system -l eks.amazonaws.com/component=coredns "cluster-autoscaler.kubernetes.io/safe-to-evict=true" || _output "annotating coredns failed"

        _output "patching coredns tolerations ..."
        kubectl patch deployment -n kube-system coredns --patch-file /app/tolerations.yml || _output "patching coredns tolerations failed"

        # nowdays set to maxUnavailable: 1
        #kubectl apply -f /app/coredns-pdb.yml || echo "coredns pdb apply failed"

        # see https://github.com/aws/amazon-vpc-cni-k8s/issues/1930
        #kubectl patch daemonset -n kube-system aws-node --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value":1}]'

        #kubectl patch deployment -n kube-system coredns --patch-file /app/coredns-topologyspreadconstraints.yml || echo "patching coredns topologySpreadConstraints failed"
        #kubectl autoscale deployment coredns -n kube-system --cpu-percent=5 --min=2 --max=9 || echo "autoscale coredns apply failed"
      ;;
      unknown)
        :
      ;;
    esac

    break
  done

  _output "15s sleep"
  sleep 15
done
