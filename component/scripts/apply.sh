#!/bin/sh
set -eu

cp /etc/vcluster-kubeconfig/config ./config
vcluster_kubeconfig=./config

echo "Setting server URL..."

kubectl --kubeconfig "$vcluster_kubeconfig" config set clusters.local.server "$VCLUSTER_SERVER_URL"

echo "Applying manifests..."

for manifest in "$@"
do
  printf "$manifest" | kubectl --kubeconfig "$vcluster_kubeconfig" apply -f - -oyaml
done

echo "Done!"
