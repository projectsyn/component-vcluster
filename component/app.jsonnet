local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vcluster;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('vcluster', params.namespace);

{
  vcluster: app,
}
