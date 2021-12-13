local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vcluster;

local script = importstr './ocp-route/create-route.sh';

local routeCreateJob = function(name, secretName, host, options)
  local jobName = name + '-create-route';

  local role = kube.Role(jobName) {
    metadata+: { namespace: options.namespace },
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
    metadata+: { namespace: options.namespace },
  };

  local roleBinding = kube.RoleBinding(jobName) {
    metadata+: { namespace: options.namespace },
    subjects_: [ serviceAccount ],
    roleRef_: role,
  };

  local routeTemplate = std.manifestJsonEx(kube._Object('route.openshift.io/v1', 'Route', name) {
    metadata+: {
      namespace: options.namespace,
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
      namespace: options.namespace,
      annotations+: {
        'argocd.argoproj.io/hook': 'PostSync',
      },
    },
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: serviceAccount.metadata.name,
          containers_+: {
            patch_crds: kube.Container(name) {
              image: '%s/%s:%s' % [ options.images.kubectl.repository, options.images.kubectl.image, options.images.kubectl.tag ],
              workingDir: '/export',
              command: [ 'sh' ],
              args: [ '-eu', '-c', script, '--', routeTemplate ],
              env: [
                { name: 'HOME', value: '/export' },
                { name: 'NAMESPACE', value: options.namespace },
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
