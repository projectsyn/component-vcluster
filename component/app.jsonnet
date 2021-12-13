local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vcluster;
local instance = inv.parameters._instance;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App(instance, params.namespace);

{
  [instance]: app,
}
