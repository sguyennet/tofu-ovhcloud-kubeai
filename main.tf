locals {
  open_webui_fqdn = "${var.open_webui_subdomain}.${var.ovh_dns_domain}"
  monitoring_fqdn = "${var.monitoring_subdomain}.${var.ovh_dns_domain}"

  # Managed databases are placed in a macro region, "GRA", while the cluster and
  # its private network live in one of its availability zones, "GRA11". The newer
  # region names, "EU-WEST-PAR" and the like, are already macro regions.
  database_region = replace(replace(var.region, "/[0-9]+$/", ""), "/-[A-Z]$/", "")

  # Every resource name is built from prefix_name, node pools included. Each pool
  # also labels its nodes with "pool = <unprefixed pool name>", which is what the
  # platform components use to land on the right nodes.
  node_pools = [for pool in var.node_pools : merge(pool, {
    name   = "${var.prefix_name}-${pool.name}"
    labels = merge(pool.labels, { pool = pool.name })
  })]

  # The registry is named once and used twice, in two different shapes: an image
  # reference wants a bare host, the image mirror wants a scheme. Accepting
  # either form on the way in means neither spelling is a silent mistake.
  vllm_registry_host = trimsuffix(trimprefix(trimprefix(var.vllm_image_registry, "https://"), "http://"), "/")
  vllm_registry_url  = local.vllm_registry_host == "" ? "" : "https://${local.vllm_registry_host}"

  # Key the pull secret is filed under. Docker Hub is the one registry an image
  # reference names implicitly, so an empty registry with credentials set means
  # Docker Hub, whose auths key is this URL rather than a bare host.
  vllm_registry_auth = local.vllm_registry_host == "" ? "https://index.docker.io/v1/" : local.vllm_registry_host

  vllm_image = var.vllm_image == "" ? "" : (
    local.vllm_registry_host == "" ? var.vllm_image : "${local.vllm_registry_host}/${var.vllm_image}"
  )

  # A pull only resolves from a peer if its registry is on this list, so a
  # registry named above is added to it. Two cases are left alone: an empty list,
  # which already means every registry and would be narrowed to one by appending
  # to it, and a registry that is on the list already.
  spegel_registries = length(var.spegel_mirrored_registries) == 0 || local.vllm_registry_url == "" ? var.spegel_mirrored_registries : distinct(
    concat(var.spegel_mirrored_registries, [local.vllm_registry_url])
  )

  ingress_lb = one([
    for lb in tolist(data.ovh_cloud_project_loadbalancers.ingress.loadbalancers) :
    lb
    if endswith(lb.name, "_${module.ingress_haproxy.namespace}_${module.ingress_haproxy.service_name}")
  ])

  # A public load balancer is reached on its floating IP, an internal one
  # (ingress_private = true) only has a VIP on the private subnet.
  ingress_ip = local.ingress_lb == null ? null : coalesce(
    try(local.ingress_lb.floating_ip.ip, null),
    local.ingress_lb.vip_address
  )

  # Node selector of the platform components: ingress controller, ExternalDNS,
  # cert-manager, the KubeAI controller and Open WebUI. Only the GPU operator and
  # the model pods are left free to land on the GPU nodes.
  platform_node_selector = {
    pool = var.platform_node_pool
  }
}

# Private network, subnet and gateway

module "private_network" {
  source = "./modules/ovhcloud/private_network"

  service_name = var.service_name
  regions      = [var.region]

  network = {
    name    = "${var.prefix_name}-private-network"
    vlan_id = var.private_network_vlan_id
  }

  subnets = [{
    name       = "${var.prefix_name}-private-subnet"
    region     = var.region
    cidr       = "10.${var.private_network_vlan_id}.0.0/16"
    gateway_ip = "10.${var.private_network_vlan_id}.0.1"
    dhcp_start = "10.${var.private_network_vlan_id}.0.2"
    dhcp_end   = "10.${var.private_network_vlan_id}.253.254"
  }]

  # The gateway gives the cluster nodes, which only have private addresses,
  # outbound access to the Internet (container registries, ACME, OVHcloud API).
  gateways = [{
    name   = "${var.prefix_name}-gateway"
    region = var.region
    size   = var.gateway_size
  }]
}

# Managed Kubernetes Service cluster

module "kubernetes" {
  source     = "./modules/ovhcloud/kubernetes"
  depends_on = [module.private_network]

  service_name = var.service_name
  region       = var.region

  private_network_routing_as_default = var.private_network_routing_as_default

  cluster = {
    name       = "${var.prefix_name}-cluster"
    version    = var.kubernetes_version
    plan       = var.kubernetes_plan
    network_id = module.private_network.network.regions_openstack_ids[var.region]
    subnet_id  = module.private_network.subnets[0].id
  }

  node_pools = local.node_pools
}

# Ingress controller

module "ingress_haproxy" {
  source     = "./modules/helm/ingress_haproxy"
  depends_on = [module.kubernetes]

  private               = var.ingress_private
  replica_count         = var.ingress_replica_count
  default_ingress_class = "true"
  node_selector         = local.platform_node_selector

  proxy_protocol_trusted_cidrs = var.ingress_proxy_protocol ? [module.private_network.subnets[0].cidr] : []
  quic                         = var.ingress_quic
}

# The public cloud load balancer created for the ingress controller service. MKS
# names it kube_service_<cluster id prefix>_<namespace>_<service>, matching on the
# suffix avoids depending on the length of that prefix, which differs between the
# free and the standard plan.
data "ovh_cloud_project_loadbalancers" "ingress" {
  depends_on = [module.ingress_haproxy]

  service_name = var.service_name
  region_name  = var.region
}

# DNS records

module "external_dns" {
  source     = "./modules/helm/external_dns"
  depends_on = [module.kubernetes]

  dns_domain    = var.ovh_dns_domain
  txt_owner_id  = "${var.prefix_name}-cluster"
  policy        = var.external_dns_policy
  node_selector = local.platform_node_selector

  ovh_endpoint               = var.ovh_api_endpoint
  api_dns_application_key    = var.ovh_api_dns_application_key
  api_dns_application_secret = var.ovh_api_dns_application_secret
  api_dns_consumer_key       = var.ovh_api_dns_consumer_key
}

# Certificates

module "cert_manager" {
  source     = "./modules/helm/cert_manager"
  depends_on = [module.kubernetes]

  dns_domain    = var.ovh_dns_domain
  email         = var.acme_email
  node_selector = local.platform_node_selector

  ovh_endpoint               = var.ovh_api_endpoint
  api_dns_application_key    = var.ovh_api_dns_application_key
  api_dns_application_secret = var.ovh_api_dns_application_secret
  api_dns_consumer_key       = var.ovh_api_dns_consumer_key
}

# NVIDIA GPU operator

module "nvidia_gpu_operator" {
  source     = "./modules/helm/nvidia_gpu_operator"
  depends_on = [module.kubernetes]

  chart_version          = var.gpu_operator_chart_version
  driver_version         = var.gpu_operator_driver_version
  use_precompiled_driver = var.gpu_operator_use_precompiled_driver
  node_selector          = local.platform_node_selector

  driver_startup_probe_initial_delay     = var.gpu_operator_driver_startup_probe_initial_delay
  driver_startup_probe_period            = var.gpu_operator_driver_startup_probe_period
  driver_startup_probe_failure_threshold = var.gpu_operator_driver_startup_probe_failure_threshold
}

# Shared filesystem

# ReadWriteMany volumes, which the block storage classes of the cluster cannot
# offer. KubeAI caches the weights of a model on one of them, so a replica
# starting on a new node reads them over the private network instead of
# downloading them from Hugging Face again.
module "csi_manila" {
  count      = var.model_cache_enabled ? 1 : 0
  source     = "./modules/ovhcloud/csi_manila"
  depends_on = [module.kubernetes]

  service_name = var.service_name
  region       = var.region

  share_network_name = "${var.prefix_name}-share-network"
  user_description   = "${var.prefix_name}-manila"

  network_id  = module.private_network.network.regions_openstack_ids[var.region]
  subnet_id   = module.private_network.subnets[0].id
  subnet_cidr = module.private_network.subnets[0].cidr

  node_selector = local.platform_node_selector
}

# Image mirror

# Every node serves the image layers it already holds to the others over the
# private network. The first pull of an image still comes from its registry, and
# through the gateway when the nodes route that way, but a node joining the pool
# afterwards, the second replica of a model above all, takes the several
# gigabytes of a vLLM image from a peer instead.
module "spegel" {
  count      = var.spegel_enabled ? 1 : 0
  source     = "./modules/helm/spegel"
  depends_on = [module.kubernetes]

  configure_containerd = var.spegel_configure_containerd
  mirrored_registries  = local.spegel_registries

  max_concurrent_downloads      = var.spegel_max_concurrent_downloads
  max_concurrent_unpacks        = var.spegel_max_concurrent_unpacks
  concurrent_layer_fetch_buffer = var.spegel_concurrent_layer_fetch_buffer
}

# Monitoring

# Prometheus scrapes what is already being exported and is not otherwise collected:
# the DCGM telemetry the GPU operator runs on every GPU node, and the metrics each
# model server serves alongside its API. Grafana is exposed the same way Open WebUI
# is, through the ingress controller with a certificate from cert-manager and a
# record from ExternalDNS.
module "monitoring" {
  count      = var.monitoring_enabled ? 1 : 0
  source     = "./modules/helm/kube_prometheus_stack"
  depends_on = [module.nvidia_gpu_operator, module.ingress_haproxy, module.external_dns, module.cert_manager]

  chart_version      = var.monitoring_chart_version
  fqdn               = local.monitoring_fqdn
  ingress_class      = module.ingress_haproxy.ingress_class
  certificate_issuer = var.certificate_issuer
  admin_user         = var.monitoring_admin_user
  admin_password     = var.monitoring_admin_password
  allow_list         = var.monitoring_allow_list

  retention    = var.monitoring_retention
  storage_size = var.monitoring_storage_size

  node_selector   = local.platform_node_selector
  dashboards_path = "${path.root}/${var.monitoring_dashboards_path}"
}

# Managed Valkey cluster

# Holds the Open WebUI configuration, its sessions and its websocket events. It is
# a service of its own, so what it keeps survives a restart of the pod, a
# reinstallation of the Helm release and a rebuild of the cluster.
module "valkey" {
  source     = "./modules/ovhcloud/databases/valkey"
  depends_on = [module.private_network]

  service_name = var.service_name
  region       = local.database_region
  description  = "${var.prefix_name}-valkey"

  valkey_version = var.valkey_version
  plan           = var.valkey_plan
  flavor         = var.valkey_flavor

  network_id = module.private_network.network.regions_openstack_ids[var.region]
  subnet_id  = module.private_network.subnets[0].id

  # The cluster nodes are the only clients, and they are all on the private subnet.
  allowed_ip = module.private_network.subnets[0].cidr
}

# Managed PostgreSQL cluster

# Holds the accounts, the conversations and the embeddings. Open WebUI defaults to
# a SQLite file on the volume of the pod, which two pods cannot share without
# corrupting it, and to a ChromaDB whose SQLite is not safe across processes
# either. Both move here, the embeddings on the pgvector extension.
module "postgresql" {
  source     = "./modules/ovhcloud/databases/postgresql"
  depends_on = [module.private_network]

  service_name = var.service_name
  region       = local.database_region
  description  = "${var.prefix_name}-postgresql"

  postgresql_version = var.postgresql_version
  plan               = var.postgresql_plan
  flavor             = var.postgresql_flavor
  database_name      = "openwebui"

  network_id = module.private_network.network.regions_openstack_ids[var.region]
  subnet_id  = module.private_network.subnets[0].id

  # The cluster nodes are the only clients, and they are all on the private subnet.
  allowed_ip = module.private_network.subnets[0].cidr
}

# Object Storage bucket

# Holds the files users upload and the images the models generate. On the volume of
# the pod they would only ever be readable by the pod that received them.
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

module "object_storage" {
  source = "./modules/ovhcloud/object_storage"

  service_name     = var.service_name
  region           = local.database_region
  user_description = "${var.prefix_name}-open-webui"

  # A bucket name has to be unique in the region, hence the suffix.
  bucket_name = "${var.prefix_name}-open-webui-${random_string.bucket_suffix.result}"
}

# Signs the Open WebUI session tokens. Generated once and kept in the state, so
# every pod is handed the same one and a restart does not sign every user out.
resource "random_password" "open_webui_secret_key" {
  length  = 64
  special = false
}

# KubeAI and Open WebUI

module "kubeai" {
  source = "./modules/helm/kubeai"
  # ExternalDNS creates the record of the Open WebUI ingress and cert-manager signs
  # its certificate, both have to be running first.
  depends_on = [module.nvidia_gpu_operator, module.ingress_haproxy, module.external_dns, module.cert_manager, module.spegel, module.csi_manila]

  fqdn               = local.open_webui_fqdn
  ingress_class      = module.ingress_haproxy.ingress_class
  certificate_issuer = var.certificate_issuer
  huggingface_token  = var.huggingface_token
  admin_email        = var.open_webui_admin_email
  admin_password     = var.open_webui_admin_password
  enable_signup      = var.open_webui_enable_signup
  default_user_role  = var.open_webui_default_user_role
  public_models      = var.open_webui_public_models
  allow_list         = var.open_webui_allow_list

  replica_count = var.open_webui_replica_count
  secret_key    = random_password.open_webui_secret_key.result

  valkey_host     = module.valkey.host
  valkey_port     = module.valkey.port
  valkey_username = module.valkey.username
  valkey_password = module.valkey.password

  postgres_host     = module.postgresql.host
  postgres_port     = module.postgresql.port
  postgres_username = module.postgresql.username
  postgres_password = module.postgresql.password
  postgres_database = module.postgresql.database_name

  s3_endpoint_url      = module.object_storage.endpoint_url
  s3_region            = module.object_storage.region
  s3_bucket            = module.object_storage.bucket_name
  s3_access_key_id     = module.object_storage.access_key_id
  s3_secret_access_key = module.object_storage.secret_access_key

  rate_limit_requests                 = var.open_webui_rate_limit_requests
  rate_limit_unauthenticated_requests = var.open_webui_rate_limit_unauthenticated_requests
  rate_limit_window                   = var.open_webui_rate_limit_window

  node_selector = local.platform_node_selector
  models_path   = "${path.root}/${var.models_path}"

  cache_profile_name = var.model_cache_profile_name
  cache_storage_size = var.model_cache_size

  # Registry and image are separate variables and joined here, so the module
  # receives one complete reference. Empty leaves the chart's own
  # vllm/vllm-openai in place; see image/README.md for building the pruned one.
  vllm_image = local.vllm_image

  # Empty username means a public repository and no pull secret at all.
  registry_host     = local.vllm_registry_auth
  registry_username = var.vllm_image_registry_username
  registry_password = var.vllm_image_registry_password


  # Empty when the cache is off, which is what makes the KubeAI module declare no
  # cache profile at all. one() rather than an index, so that the expression still
  # reads when the module holds no instance.
  cache_storage_class = var.model_cache_enabled ? one(module.csi_manila[*].storage_class_name) : ""
}
