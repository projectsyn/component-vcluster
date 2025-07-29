/*
* Patches the OCP route.
*
* Routes do not support reading certificates from secrets. Thus
* certificates have to be known before creating a route or patched
* in afterwards. Since the route is automatically created from
* the ingress, we will patch the route afterwards.
* The clusters serving certificate is only known after startup.
* So we create a job that:
* - Mounts the vclusters kubeconfig
* - Reads the clusters self signed serving certificate from it
* - Patches the route
*/

local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.vcluster;
local common = import 'common.libsonnet';

local script = importstr './scripts/patch-route.sh';

local routePatchJob = function(name, secretName, host)
  local jobName = name + '-create-route';

  local role = kube.Role(jobName) {
    metadata+: { namespace: params.namespace },
    rules: [
      {
        apiGroups: [ 'route.openshift.io' ],
        resources: [ 'routes', 'routes/custom-host' ],
        verbs: [ '*' ],
      },
      {
        apiGroups: [ 'cert-manager.io' ],
        resources: [ 'certificates' ],
        verbs: [ 'get' ],
      },
    ],
  };

  local serviceAccount = kube.ServiceAccount(jobName) {
    metadata+: { namespace: params.namespace },
  };

  local roleBinding = kube.RoleBinding(jobName) {
    metadata+: { namespace: params.namespace },
    subjects_: [ serviceAccount ],
    roleRef_: role,
  };

  local job = kube.Job(jobName) {
    metadata+: {
      namespace: params.namespace,
      annotations+: {
        'argocd.argoproj.io/hook': 'PostSync',
      },
    },
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: serviceAccount.metadata.name,
          containers_+: {
            create_route: kube.Container(name) {
              image: common.formatImage(params.images.oc),
              workingDir: '/export',
              command: [ 'sh' ],
              args: [ '-eu', '-c', script ],
              env: [
                { name: 'HOME', value: '/export' },
                { name: 'NAMESPACE', value: params.namespace },
                { name: 'VCLUSTER_NAME', value: name },
              ],
              volumeMounts: [
                { name: 'export', mountPath: '/export' },
                { name: 'vcluster-config', mountPath: '/etc/vcluster-config', readOnly: true },
              ],
            },
          },
          volumes+: [
            { name: 'export', emptyDir: {} },
            { name: 'vcluster-config', secret: { secretName: secretName } },
          ],
        },
      },
    },
  };
  [
    serviceAccount,
    role,
    roleBinding,
    job,
  ];

{
  RoutePatchJob: routePatchJob,
}
