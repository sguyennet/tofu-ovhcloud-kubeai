resource "helm_release" "external-dns" {
  name      = "external-dns"
  namespace = var.namespace

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.chart_version

  create_namespace = true

  timeout = 600
  wait    = true

  set = concat([
    {
      name  = "provider.name"
      value = "ovh"
    },
    {
      name  = "policy"
      value = var.policy
    },
    {
      name  = "registry"
      value = "txt"
    },
    {
      name  = "txtOwnerId"
      value = var.txt_owner_id
    },
    {
      name  = "txtPrefix"
      value = "extdns-"
    },
    {
      name  = "domainFilters[0]"
      value = var.dns_domain
    },
    {
      name  = "extraArgs.ovh-endpoint"
      value = var.ovh_endpoint
    },
    {
      name  = "env[0].name"
      value = "OVH_APPLICATION_KEY"
    },
    {
      name  = "env[1].name"
      value = "OVH_APPLICATION_SECRET"
    },
    {
      name  = "env[2].name"
      value = "OVH_CONSUMER_KEY"
    }
    ],
    [for index, source in var.sources : {
      name  = "sources[${index}]"
      value = source
    }],
    [for key, value in var.node_selector : {
      name  = "nodeSelector.${replace(key, ".", "\\.")}"
      value = value
    }]
  )

  set_sensitive = [
    {
      name  = "env[0].value"
      type  = "string"
      value = var.api_dns_application_key
    },
    {
      name  = "env[1].value"
      type  = "string"
      value = var.api_dns_application_secret
    },
    {
      name  = "env[2].value"
      type  = "string"
      value = var.api_dns_consumer_key
    }
  ]
}
