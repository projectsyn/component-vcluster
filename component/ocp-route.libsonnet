/*
* Creates a re-encrypting OCP route.
*
* Routes do not support reading certificates from secrets. Thus
* certificates have to be known before creating a route.
* The clusters serving certificate is only known after startup.
* So we create a job that:
* - Mounts the vclusters kubeconfig
* - Reads the clusters self signed serving certificate from it
* - Inserts the certificate into the route template
* - Creates the route and sets ownership to the vcluster StatefulSet
*/

local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.vcluster;
local common = import 'common.libsonnet';

local script = importstr './scripts/create-route.sh';

local routeCreateJob = function(name, secretName, host)
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
        apiGroups: [ 'apps' ],
        resources: [ 'statefulsets' ],
        resourceNames: [ name ],
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

  local routeTemplate = std.manifestJsonEx(kube._Object('route.openshift.io/v1', 'Route', name) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      host: host,
      path: '/',
      port: {
        targetPort: 'https',
      },
      tls: {
        insecureEdgeTerminationPolicy: 'None',
        termination: 'reencrypt',
      },
      to: {
        kind: 'Service',
        name: name,
        weight: 100,
      },
      wildcardPolicy: 'None',
    },
  }, '');

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
              image: common.formatImage(params.images.kubectl),
              workingDir: '/export',
              command: [ 'sh' ],
              args: [ '-eu', '-c', script, '--', routeTemplate ],
              env: [
                { name: 'HOME', value: '/export' },
                { name: 'NAMESPACE', value: params.namespace },
                { name: 'VCLUSTER_STS_NAME', value: name },
              ],
              volumeMounts: [
                { name: 'export', mountPath: '/export' },
                { name: 'kubeconfig', mountPath: '/etc/vcluster-kubeconfig', readOnly: true },
              ],
            },
          },
          volumes+: [
            { name: 'export', emptyDir: {} },
            { name: 'kubeconfig', secret: { secretName: secretName } },
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
  RouteCreateJob: routeCreateJob,
}
