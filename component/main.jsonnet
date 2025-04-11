// main template for vcluster
local cluster = import 'cluster.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vcluster;
local instance = inv.parameters._instance;
local ocpRoute = import 'ocp-route.libsonnet';
local postSetup = import 'post-setup.libsonnet';

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';

local sccRole = kube.Role('use-nonroot-v2') {
  metadata+: {
    namespace: params.namespace,
  },
  rules: [
    {
      apiGroups: [
        'security.openshift.io',
      ],
      resourceNames: [
        'nonroot-v2',
      ],
      resources: [
        'securitycontextconstraints',
      ],
      verbs: [
        'use',
      ],
    },
  ],
};
local sccRoleBinding = kube.RoleBinding('vcluster-use-nonroot-v2') {
  metadata+: {
    annotations+: {
      'vcluster.syn.tools/description': 'Allow vcluster to sync pods with arbitrary nonroot users by allowing the default ServiceAccount to use the nonroot-v2 scc',
    },
    namespace: params.namespace,
  },
  roleRef_: sccRole,
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'vc-%s' % instance,
      namespace: params.namespace,
    },
  ],
};


// Define outputs below
{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: com.makeMergeable(params.namespaceMetadata),
  },
  [if isOpenshift && params.ingress.enabled && params.ingress.host != null then '11_ocp_route']: ocpRoute.RoutePatchJob(instance, 'vc-%s' % instance, params.ingress.host),
  [if params.syn.registration_url != null then '11_synthesize']: postSetup.Synthesize(instance, 'vc-%s' % instance, params.syn.registration_url),
  [if isOpenshift then '20_scc_role']: sccRole,
  [if isOpenshift then '20_scc_role_binding']: sccRoleBinding,
}
