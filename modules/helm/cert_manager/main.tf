locals {
  # ClusterIssuers created by the OVHcloud webhook, both solving DNS-01
  # challenges through the OVHcloud DNS API.
  issuers = [
    {
      name            = "letsencrypt-production"
      acme_server_url = "https://acme-v02.api.letsencrypt.org/directory"
    },
    {
      name            = "letsencrypt-staging"
      acme_server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"
    }
  ]
}

resource "helm_release" "cert-manager" {
  name      = "cert-manager"
  namespace = var.namespace

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version

  create_namespace = true

  timeout = 600
  wait    = true

  set = concat([
    {
      name  = "crds.enabled"
      value = "true"
    },
    {
      name  = "crds.keep"
      value = "false"
    }
    ],
    # global.nodeSelector is inherited by every cert-manager component
    # (controller, webhook, cainjector and startupapicheck).
    [for key, value in var.node_selector : {
      name  = "global.nodeSelector.${replace(key, ".", "\\.")}"
      value = value
    }]
  )
}

resource "helm_release" "cert-manager-webhook-ovh" {
  name      = "cert-manager-webhook-ovh"
  namespace = var.namespace

  repository = "https://aureq.github.io/cert-manager-webhook-ovh/"
  chart      = "cert-manager-webhook-ovh"
  version    = var.webhook_chart_version

  timeout = 600
  wait    = true

  set = concat([
    {
      name  = "groupName"
      type  = "string"
      value = var.dns_domain
    },
    {
      name  = "certManager.namespace"
      type  = "string"
      value = var.namespace
    }
    ],
    flatten([for index, issuer in local.issuers : [
      {
        name  = "issuers[${index}].name"
        type  = "string"
        value = issuer.name
      },
      # The chart values schema expects a real boolean here.
      {
        name  = "issuers[${index}].create"
        type  = "auto"
        value = "true"
      },
      {
        name  = "issuers[${index}].kind"
        type  = "string"
        value = "ClusterIssuer"
      },
      {
        name  = "issuers[${index}].acmeServerUrl"
        type  = "string"
        value = issuer.acme_server_url
      },
      {
        name  = "issuers[${index}].email"
        type  = "string"
        value = var.email
      },
      {
        name  = "issuers[${index}].ovhEndpointName"
        type  = "string"
        value = var.ovh_endpoint
      },
      {
        name  = "issuers[${index}].ovhAuthenticationMethod"
        type  = "string"
        value = "application"
      },
      {
        name  = "issuers[${index}].ovhAuthentication.applicationKey"
        type  = "string"
        value = var.api_dns_application_key
      }
    ]]),
    [for key, value in var.node_selector : {
      name  = "pod.selectors.nodeSelector.${replace(key, ".", "\\.")}"
      type  = "string"
      value = value
    }]
  )

  set_sensitive = flatten([for index, issuer in local.issuers : [
    {
      name  = "issuers[${index}].ovhAuthentication.applicationSecret"
      type  = "string"
      value = var.api_dns_application_secret
    },
    {
      name  = "issuers[${index}].ovhAuthentication.applicationConsumerKey"
      type  = "string"
      value = var.api_dns_consumer_key
    }
  ]])

  depends_on = [helm_release.cert-manager]
}
