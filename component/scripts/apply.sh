#!/bin/sh
set -eu

vcluster_kubeconfig=/etc/vcluster-kubeconfig/config

echo "Applying manifests..."

for manifest in "$@"
do
  printf "$manifest" | kubectl --kubeconfig "$vcluster_kubeconfig" apply -f - -oyaml
done

echo "Done!"
