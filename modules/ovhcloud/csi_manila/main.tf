# The Manila driver hands the actual mounting to the generic NFS driver, so that
# one goes in first. Its own node plugin already tolerates every taint, which is
# what lets it run on the GPU nodes as well.
resource "helm_release" "csi_driver_nfs" {
  name      = "csi-driver-nfs"
  namespace = var.namespace

  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  version    = var.csi_driver_nfs_chart_version

  timeout = 600
  wait    = true
}

# The driver calls the shared filesystem API to create, mount and grow shares, and
# authenticates as a user of its own. share_operator is the role that covers that
# service and nothing else, so the credentials the driver holds cannot reach the
# rest of the project.
resource "ovh_cloud_project_user" "manila" {
  service_name = var.service_name
  description  = var.user_description
  role_name    = var.role_name
}

resource "kubectl_manifest" "credentials" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = local.secret_name
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      "os-authURL"         = "https://auth.cloud.ovh.net/v3"
      "os-region"          = var.region
      "os-userName"        = ovh_cloud_project_user.manila.username
      "os-password"        = ovh_cloud_project_user.manila.password
      "os-domainName"      = "default"
      "os-projectID"       = var.service_name
      "os-projectDomainID" = "default"
    }
  })

  sensitive_fields = ["stringData.os-password"]
}

# Binds the shares to the private network of the cluster: a node then mounts them
# over the private subnet, at local network speed, rather than over the internet.
resource "openstack_sharedfilesystem_sharenetwork_v2" "share_network" {
  name              = var.share_network_name
  region            = var.region
  neutron_net_id    = var.network_id
  neutron_subnet_id = var.subnet_id
}

locals {
  secret_name = "csi-manila-secrets"

  # An operator of Exists carries no value, and a null one is not something the
  # API accepts, so the empty keys are dropped rather than rendered.
  tolerations = [for toleration in var.tolerations : {
    for key, value in toleration : key => value if value != null
  }]
}

resource "helm_release" "manila_csi" {
  depends_on = [helm_release.csi_driver_nfs, kubectl_manifest.credentials]

  name      = "openstack-manila-csi"
  namespace = var.namespace

  repository = "https://kubernetes.github.io/cloud-provider-openstack"
  chart      = "openstack-manila-csi"
  version    = var.manila_csi_chart_version

  timeout = 600
  wait    = true

  values = [yamlencode({
    csimanila = {
      runtimeConfig = {
        enabled = true
        # A share is exported on several addresses. This keeps the driver to the
        # one on the private subnet of the cluster, which is the only one the
        # nodes can reach.
        jsonData = jsonencode({
          nfs = {
            matchExportLocationAddress = var.subnet_cidr
          }
        })
      }
    }

    # The node plugin has to run wherever a share is mounted, the GPU nodes
    # included, and those are tainted. The chart tolerates nothing by default.
    nodeplugin = {
      tolerations = local.tolerations
    }

    # The controller only talks to the OpenStack API, so it belongs with the
    # other platform components rather than on a GPU node.
    controllerplugin = {
      nodeSelector = var.node_selector
    }
  })]
}

# ReadWriteMany, which is what a model cache read by replicas on several nodes
# needs and what no block storage class can offer.
resource "kubectl_manifest" "storage_class" {
  depends_on = [helm_release.manila_csi]

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = var.storage_class_name
    }
    provisioner          = "nfs.manila.csi.openstack.org"
    allowVolumeExpansion = true
    reclaimPolicy        = "Delete"
    parameters = merge(
      {
        type           = var.share_type
        shareNetworkID = openstack_sharedfilesystem_sharenetwork_v2.share_network.id
        # Addresses allowed to mount the share.
        "nfs-shareClient" = var.subnet_cidr
      },
      # Every stage of the driver reads the same OpenStack credentials.
      merge([for stage in ["provisioner", "controller-expand", "node-stage", "node-publish"] : {
        "csi.storage.k8s.io/${stage}-secret-name"      = local.secret_name
        "csi.storage.k8s.io/${stage}-secret-namespace" = var.namespace
      }]...)
    )
  })
}
