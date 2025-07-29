local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.vcluster;
local common = import 'common.libsonnet';

local synthesize = function(name, secretName, url)
  local jobName = '%s-synthesize' % name;
  kube.Job(jobName) {
    metadata+: {
      namespace: params.namespace,
      annotations+: {
        'argocd.argoproj.io/hook': 'PostSync',
      },
    },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            patch_crds: kube.Container(jobName) {
              image: common.formatImage(params.images.oc),
              workingDir: '/export',
              command: [ 'sh' ],
              args: [ '-eu', '-c', importstr './scripts/synthesize.sh', '--', url ],
              env: [
                { name: 'HOME', value: '/export' },
                { name: 'VCLUSTER_SERVER_URL', value: 'https://%s:443' % name },
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

{
  Synthesize: synthesize,
}
