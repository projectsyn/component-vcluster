// main template for vcluster
local cluster = import 'cluster.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vcluster;
local instance = inv.parameters._instance;

// Define outputs below
{
  '00_namespace': kube.Namespace(params.namespace),
  '10_cluster': cluster.Cluster(instance, params),
}
