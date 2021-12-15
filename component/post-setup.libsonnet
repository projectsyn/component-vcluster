local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.vcluster;

local synfection = function(jobName, secretName, url)
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
              image: '%s/%s:%s' % [ params.images.kubectl.repository, params.images.kubectl.image, params.images.kubectl.tag ],
              workingDir: '/export',
              command: [ 'sh' ],
              args: [ '-eu', '-c', importstr './scripts/synfection.sh', '--', url ],
              env: [
                { name: 'HOME', value: '/export' },
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

local applyManifests = function(jobName, secretName, manifests)
  local manifestArray = if std.isArray(manifests) then
    manifests
  else if std.isObject(manifests) then
    std.objectValues(manifests)
  else
    error 'Manifests must be array or object'
  ;
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
              image: '%s/%s:%s' % [ params.images.kubectl.repository, params.images.kubectl.image, params.images.kubectl.tag ],
              workingDir: '/export',
              command: [ 'sh' ],
              args: [ '-eu', '-c', importstr './scripts/apply.sh', '--' ] + std.map(function(m) std.manifestJsonEx(m, ''), manifestArray),
              env: [
                { name: 'HOME', value: '/export' },
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
  Synfection: synfection,
  ApplyManifests: applyManifests,
}
