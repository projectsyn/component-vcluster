local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local ocpRoute = import 'ocp-route.libsonnet';
local postSetup = import 'post-setup.libsonnet';
local inv = kap.inventory();
local common = import 'common.libsonnet';
// The hiera parameters for the component
local params = inv.parameters.vcluster;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local cluster = function(name, options)
  local sa = kube.ServiceAccount('vc-' + name) {
    metadata+: {
      namespace: options.namespace,
    },
  };
  local role = kube.Role(name) {
    metadata+: {
      namespace: options.namespace,
    },
    rules: [
      {
        apiGroups: [
          '',
        ],
        resources: [
          'configmaps',
          'secrets',
          'services',
          'pods',
          'pods/attach',
          'pods/portforward',
          'pods/exec',
          'endpoints',
          'persistentvolumeclaims',
        ],
        verbs: [
          'create',
          'delete',
          'patch',
          'update',
          'get',
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'events',
          'pods/log',
        ],
        verbs: [
          'get',
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'networking.k8s.io',
        ],
        resources: [
          'ingresses',
        ],
        verbs: [
          'create',
          'delete',
          'patch',
          'update',
          'get',
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'networking.k8s.io',
        ],
        resources: [
          'ingressclasses',
        ],
        verbs: [
          'get',
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'apps',
        ],
        resources: [
          'statefulsets',
          'replicasets',
          'deployments',
        ],
        verbs: [
          'get',
          'list',
          'watch',
        ],
      },
    ] + if isOpenshift then
      [
        {
          apiGroups: [
            '',
          ],
          resources: [
            'endpoints/restricted',
          ],
          verbs: [
            'create',
          ],
        },
      ] else [],
  };
  local roleBinding = kube.RoleBinding(name) {
    metadata+: {
      namespace: options.namespace,
    },
    subjects_: [ sa ],
    roleRef_: role,
  };

  local service = kube.Service(name) {
    metadata+: {
      namespace: options.namespace,
    },
    spec: {
      type: 'ClusterIP',
      ports: [
        {
          name: 'https',
          port: 443,
          targetPort: 8443,
          protocol: 'TCP',
        },
      ],
      selector: {
        app: 'vcluster',
        release: name,
      },
    },
  };

  local headlessService = kube.Service(name + '-headless') {
    metadata+: {
      namespace: options.namespace,
    },
    spec: {
      ports: [
        {
          name: 'https',
          port: 443,
          targetPort: 8443,
          protocol: 'TCP',
        },
      ],
      clusterIP: 'None',
      selector: {
        app: 'vcluster',
        release: name,
      },
    },
  };

  local initManifestsCM = kube.ConfigMap(name + '-init-manifests') {
    local manifests = options.additional_manifests,
    local manifestArray = if std.isArray(manifests) then
      manifests
    else if std.isObject(manifests) then
      std.objectValues(manifests)
    else
      error 'Manifests must be array or object'
    ,

    metadata+: {
      namespace: options.namespace,
    },
    data: {
      manifests: std.manifestYamlStream(manifestArray, false, false),
    },
  };

  local statefulSet = kube.StatefulSet(name) {
    metadata+: {
      namespace: options.namespace,
    },
    spec: {
      serviceName: name + '-headless',
      replicas: 1,
      selector: {
        matchLabels: {
          app: 'vcluster',
          release: name,
        },
      },
      volumeClaimTemplates:
        if options.storage.persistence then [
          {
            metadata: {
              name: 'data',
            },
            spec: {
              accessModes: [ 'ReadWriteOnce' ],
              storageClassName: options.storage.class_name,
              resources: {
                requests: {
                  storage: options.storage.size,
                },
              },
            },
          },
        ] else [],
      template: {
        metadata: {
          labels: {
            app: 'vcluster',
            release: name,
          },
        },
        spec: {
          terminationGracePeriodSeconds: 10,
          nodeSelector: {},
          affinity: {},
          tolerations: [],
          serviceAccountName: 'vc-' + name,
          volumes: [
            {
              name: 'coredns',
              configMap: {
                name: 'vc-%s-coredns' % name,
                defaultMode: 420,
              },
            },
            {
              name: 'etc-rancher',
              emptyDir: {},
            },
          ] + if !options.storage.persistence then [
            {
              name: 'data',
              emptyDir: {},
            },
          ] else [],
          local tlsSANs = [
            '--tls-san=%s.%s.svc.cluster.local' % [ name, options.namespace ],
            '--tls-san=%s.%s.svc' % [ name, options.namespace ],
            '--tls-san=%s.%s' % [ name, options.namespace ],
            '--tls-san=%s' % [ name ],
          ],
          containers: [
            {
              image: common.formatImage(options.images.k3s),
              name: 'vcluster',
              command: [
                '/bin/k3s',
              ],
              assert options.host_service_cidr != null : |||
                `host_service_cidr` must be set.

                You can find out a host cluster's service CIDR by deploying a service with an invalid ClusterIP (such as 1.1.1.1).
                $ kubectl create svc clusterip check-service-cidr --clusterip=1.1.1.1 --tcp=5678:5678
                The error message shows the host cluster's service CIDR:
                > The Service "check-service-cidr" is invalid: spec.clusterIPs: Invalid value: []string{"1.1.1.1"}.... The range of valid IPs is 10.96.0.0/12.
              |||,
              args: [
                'server',
                '--write-kubeconfig=/data/k3s-config/kube-config.yaml',
                '--data-dir=/data',
                '--disable=traefik,servicelb,metrics-server,local-storage,coredns',
                '--disable-network-policy',
                '--disable-agent',
                '--disable-scheduler',
                '--disable-cloud-controller',
                '--flannel-backend=none',
                '--service-cidr=%s' % options.host_service_cidr,
                '--kube-controller-manager-arg=controllers=*,-nodeipam,-nodelifecycle,-persistentvolume-binder,-attachdetach,-persistentvolume-expander,-cloud-node-lifecycle',
              ] + tlsSANs + options.k3s.additional_args,
              env: [],
              securityContext: {
                allowPrivilegeEscalation: false,
              },
              volumeMounts: [
                {
                  mountPath: '/data',
                  name: 'data',
                },
                {
                  mountPath: '/etc/rancher',
                  name: 'etc-rancher',
                },
              ],
              resources: {
                limits: {
                  memory: '2Gi',
                },
                requests: {
                  cpu: '200m',
                  memory: '256Mi',
                },
              },
            },
            {
              name: 'syncer',
              image: common.formatImage(options.images.syncer),
              args: [
                '--name=' + name,
                '--out-kube-config-secret=vc-%s-kubeconfig' % name,
                '--sync=ingresses',
              ] + tlsSANs + options.syncer.additional_args,
              livenessProbe: {
                httpGet: {
                  path: '/healthz',
                  port: 8443,
                  scheme: 'HTTPS',
                },
                failureThreshold: 10,
                initialDelaySeconds: 60,
                periodSeconds: 2,
              },
              readinessProbe: {
                httpGet: {
                  path: '/readyz',
                  port: 8443,
                  scheme: 'HTTPS',
                },
                failureThreshold: 30,
                periodSeconds: 2,
              },
              securityContext: {
                allowPrivilegeEscalation: false,
              },
              env: [],
              volumeMounts: [
                {
                  mountPath: '/data',
                  name: 'data',
                  readOnly: true,
                },
                {
                  mountPath: '/manifests/coredns',
                  name: 'coredns',
                  readOnly: true,
                },
              ],
              resources: {
                limits: {
                  memory: '1Gi',
                },
                requests: {
                  cpu: '100m',
                  memory: '128Mi',
                },
              },
            },
          ],
        },
      },
    },
  };

  local ingress = kube._Object('networking.k8s.io/v1', 'Ingress', name) {
    metadata+: {
      namespace: options.namespace,
      annotations+: options.ingress.annotations,
      labels+: options.ingress.labels,
    },
    spec: {
      rules: [
        {
          host: options.ingress.host,
          http: {
            paths: [
              {
                backend: {
                  service: {
                    name: name,
                    port: {
                      name: 'https',
                    },
                  },
                },
                path: '/',
                pathType: 'Prefix',
              },
            ],
          },
        },
      ],
      tls: [
        {
          hosts: [
            options.ingress.host,
          ],
          secretName: name + '-tls',
        },
      ],
    },
  };

  std.filter(function(m) m != null, [
    sa,
    role,
    roleBinding,
    service,
    headlessService,
    statefulSet,
    initManifestsCM,
    (import 'coredns.libsonnet').corednsConfigMap(name, options.namespace),
    if options.ingress.host != null then ingress,
    if options.syn.registration_url != null then postSetup.Synthesize(name, 'vc-%s-kubeconfig' % name, options.syn.registration_url),
  ] + if options.ocp_route.host != null then ocpRoute.RouteCreateJob(name, 'vc-%s-kubeconfig' % name, options.ocp_route.host) else []);

{
  Cluster: cluster,
}
