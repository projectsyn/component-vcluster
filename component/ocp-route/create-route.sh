#!/bin/sh
set -eu

vcluster_kubeconfig=/etc/vcluster-kubeconfig/config

echo "Using kubeconfig: $vcluster_kubeconfig"

cert=$(kubectl --kubeconfig $vcluster_kubeconfig config view '-o=template={{(index (index .clusters 0).cluster "certificate-authority-data") | base64decode}}' --raw)

echo "Found certificate:\n$cert"

echo "Looking for StatefulSet.apps/${VCLUSTER_STS_NAME}..."

owner=$(kubectl get StatefulSet.apps "$VCLUSTER_STS_NAME" -ojson | jq '{kind: .kind, apiVersion: .apiVersion, name: .metadata.name, uid: .metadata.uid}')

echo "Found StatefulSet as owner: $owner"

echo "Applying route..."

printf "$1" \
    | jq \
        --arg     cert  "$cert" \
        --argjson owner "$owner" \
        '.metadata.ownerReferences = [$owner] | .spec.tls.destinationCACertificate = $cert' \
    | kubectl apply -f - -oyaml

echo "Done!"
