#!/bin/sh
set -eu

cp /etc/vcluster-kubeconfig/config ./config
vcluster_kubeconfig=./config

echo "Setting server URL..."

kubectl --kubeconfig "$vcluster_kubeconfig" config set clusters.kubernetes.server "$VCLUSTER_SERVER_URL"

echo "Checking for namespace 'syn'..."

exists=$(kubectl --kubeconfig "$vcluster_kubeconfig" get namespace syn --ignore-not-found)
if [ -n "$exists" ]; then
  echo "Namespace 'syn' exists. Skipping synthesize."
  exit 0
fi

echo "Starting synthesize..."

kubectl --kubeconfig "$vcluster_kubeconfig" apply -f "$1"

echo "Done!"
