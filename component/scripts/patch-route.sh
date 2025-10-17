#!/bin/sh
set -eu

cert=/etc/vcluster-config/certificate-authority

echo "Using ca: $cert"

echo "Looking for routes.route.openshift.io for ${VCLUSTER_NAME}..."

route_name=$(kubectl -n "$NAMESPACE" get routes.route.openshift.io -ojson | jq -r '.items[].metadata | select(.ownerReferences !=null) | select(.ownerReferences[].name=="'"${VCLUSTER_NAME}"'") | .name')

echo "Found route: $route_name"

echo "Check if route is already patched"

patched=$(kubectl -n "$NAMESPACE" get route "$route_name" -o jsonpath='{.spec.tls.destinationCACertificate}')

if [ "$patched" = "$(cat $cert)" ]; then
    echo "Route is already patched. Nothing to do"
    exit
fi

echo "Waiting for route to have a proper certificate"

i=0
while [ "$i" -lt 100 ]; do
    certificate_status=$(kubectl -n "$NAMESPACE" get certificate "$VCLUSTER_NAME"-tls -o jsonpath='{.status.conditions[0].type}')
    if [ "$certificate_status" = "Ready" ]; then break; fi
    sleep 10
    $i++
done

if [ "$certificate_status" != "Ready" ]; then
    echo "Certificate is not ready. Please check status of certificate issuance."
    exit 1
fi

patch_cert="$(cat ${cert} | sed 's/$/\\n/' | tr -d '\n')"

patch_file=$(mktemp)

printf '%s\n' '{"spec":{"tls":{"destinationCACertificate":"'"$(printf '%s\n' "${patch_cert}")"'"}}}' > "${patch_file}"

echo "Patching route..."

kubectl -n "$NAMESPACE" patch route "$route_name" --patch-file "${patch_file}"

rm "${patch_file}"

echo "Done!"
