local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local common = import 'common.libsonnet';
// The hiera parameters for the component
local params = inv.parameters.vcluster;

local corednsConfigMap =
  function(name, namespace)
    kube.ConfigMap('vc-%s-coredns' % name) {
      metadata+: {
        namespace: namespace,
      },
      data: {
        // The deployment has some variables in there that get modified by vcluster.
        // It is not valid yaml, so we need to use a string.
        // The Helm chart does use a string too.
        'coredns.yaml': |||
          apiVersion: v1
          kind: ServiceAccount
          metadata:
            name: coredns
            namespace: kube-system
          ---
          apiVersion: rbac.authorization.k8s.io/v1
          kind: ClusterRole
          metadata:
            labels:
              kubernetes.io/bootstrapping: rbac-defaults
            name: system:coredns
          rules:
            - apiGroups:
                - ""
              resources:
                - endpoints
                - services
                - pods
                - namespaces
              verbs:
                - list
                - watch
            - apiGroups:
                - discovery.k8s.io
              resources:
                - endpointslices
              verbs:
                - list
                - watch
          ---
          apiVersion: rbac.authorization.k8s.io/v1
          kind: ClusterRoleBinding
          metadata:
            annotations:
              rbac.authorization.kubernetes.io/autoupdate: "true"
            labels:
              kubernetes.io/bootstrapping: rbac-defaults
            name: system:coredns
          roleRef:
            apiGroup: rbac.authorization.k8s.io
            kind: ClusterRole
            name: system:coredns
          subjects:
            - kind: ServiceAccount
              name: coredns
              namespace: kube-system
          ---
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: coredns
            namespace: kube-system
          data:
            Corefile: |
              .:1053 {
                  {{.LOG_IN_DEBUG}}
                  errors
                  health
                  ready
                  kubernetes cluster.local in-addr.arpa ip6.arpa {
                    pods insecure
                    fallthrough in-addr.arpa ip6.arpa
                  }
                  hosts /etc/coredns/NodeHosts {
                    ttl 60
                    reload 15s
                    fallthrough
                  }
                  prometheus :9153
                  forward . /etc/resolv.conf
                  cache 30
                  loop
                  reload
                  loadbalance
              }

              import /etc/coredns/custom/*.server
            NodeHosts: ""
          ---
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: coredns
            namespace: kube-system
            labels:
              k8s-app: kube-dns
              kubernetes.io/name: "CoreDNS"
          spec:
            replicas: 1
            strategy:
              type: RollingUpdate
              rollingUpdate:
                maxUnavailable: 1
            selector:
              matchLabels:
                k8s-app: kube-dns
            template:
              metadata:
                labels:
                  k8s-app: kube-dns
              spec:
                priorityClassName: "system-cluster-critical"
                serviceAccountName: coredns
                nodeSelector:
                  kubernetes.io/os: linux
                topologySpreadConstraints:
                  - maxSkew: 1
                    topologyKey: kubernetes.io/hostname
                    whenUnsatisfiable: DoNotSchedule
                    labelSelector:
                      matchLabels:
                        k8s-app: kube-dns
                containers:
                  - name: coredns
                    image: {{.IMAGE}}
                    imagePullPolicy: IfNotPresent
                    resources:
                      limits:
                        cpu: 1000m
                        memory: 170Mi
                      requests:
                        cpu: 100m
                        memory: 70Mi
                    args: [ "-conf", "/etc/coredns/Corefile" ]
                    volumeMounts:
                      - name: config-volume
                        mountPath: /etc/coredns
                        readOnly: true
                      - name: custom-config-volume
                        mountPath: /etc/coredns/custom
                        readOnly: true
                    ports:
                      - containerPort: 1053
                        name: dns
                        protocol: UDP
                      - containerPort: 1053
                        name: dns-tcp
                        protocol: TCP
                      - containerPort: 9153
                        name: metrics
                        protocol: TCP
                    securityContext:
                      runAsNonRoot: true
                      runAsUser: {{.RUN_AS_USER}}
                      runAsGroup: {{.RUN_AS_GROUP}}
                      allowPrivilegeEscalation: false
                      capabilities:
                        drop:
                          - ALL
                      readOnlyRootFilesystem: true
                    livenessProbe:
                      httpGet:
                        path: /health
                        port: 8080
                        scheme: HTTP
                      initialDelaySeconds: 60
                      periodSeconds: 10
                      timeoutSeconds: 1
                      successThreshold: 1
                      failureThreshold: 3
                    readinessProbe:
                      httpGet:
                        path: /ready
                        port: 8181
                        scheme: HTTP
                      initialDelaySeconds: 0
                      periodSeconds: 2
                      timeoutSeconds: 1
                      successThreshold: 1
                      failureThreshold: 3
                dnsPolicy: Default
                volumes:
                  - name: config-volume
                    configMap:
                      name: coredns
                      items:
                        - key: Corefile
                          path: Corefile
                        - key: NodeHosts
                          path: NodeHosts
                  - name: custom-config-volume
                    configMap:
                      name: coredns-custom
                      optional: true
          ---
          apiVersion: v1
          kind: Service
          metadata:
            name: kube-dns
            namespace: kube-system
            annotations:
              prometheus.io/port: "9153"
              prometheus.io/scrape: "true"
            labels:
              k8s-app: kube-dns
              kubernetes.io/cluster-service: "true"
              kubernetes.io/name: "CoreDNS"
          spec:
            selector:
              k8s-app: kube-dns
            type: ClusterIP
            ports:
              - name: dns
                port: 53
                targetPort: 1053
                protocol: UDP
              - name: dns-tcp
                port: 53
                targetPort: 1053
                protocol: TCP
              - name: metrics
                port: 9153
                protocol: TCP
        |||,
      },
    };

{
  corednsConfigMap: corednsConfigMap,
}
