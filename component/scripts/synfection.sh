#!/bin/sh
set -eu

vcluster_kubeconfig=/etc/vcluster-kubeconfig/config

echo "Checking for namespace 'syn'..."

exists=$(kubectl --kubeconfig "$vcluster_kubeconfig" get namespace syn --ignore-not-found)
if [ -n "$exists" ]; then
  echo "Namespace 'syn' exists. Skipping synfection."
  exit 0
fi

echo "Starting synfection..."

kubectl --kubeconfig "$vcluster_kubeconfig" apply -f "$1"

echo "Done!"
