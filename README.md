# KubeAI on OVHcloud Managed Kubernetes: LLM inference behind Open WebUI

Deploys a complete, private LLM inference platform on OVHcloud Public Cloud:

* a **Managed Kubernetes Service** cluster on a vRack private network, with a
  platform node pool and an autoscaling GPU node pool
* the **NVIDIA GPU operator**, installing a precompiled driver on every GPU node
* **Spegel**, so a new node takes image layers from a peer over the private
  network instead of from the registry
* **HAProxy ingress**, **cert-manager** and **ExternalDNS**, which publish and
  sign the Open WebUI hostname on your own DNS zone
* managed **Valkey**, **PostgreSQL** and **Object Storage** holding the Open WebUI
  sessions, database and uploads, so the pods keep nothing of value
* a **shared filesystem** (Manila) caching the model weights, downloaded from
  Hugging Face once and read over the private network by every replica afterwards
* **KubeAI**, serving vLLM models that scale on request load, and **Open WebUI**
  in front of them

**Requirements:**

You need the following:

* [OpenTofu](https://opentofu.org/) 1.6 or later installed
* [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
* An [OVHcloud Public Cloud project](https://www.ovhcloud.com/en/public-cloud/)
* An [OVHcloud vRack private network](https://www.ovhcloud.com/en/network/vrack/)
* An [OVHcloud domain name](https://www.ovhcloud.com/en/domains/), whose DNS zone
  is hosted at OVHcloud
* GPU quota in the region for the flavor declared in `node_pools`
* An [OpenStack user](https://docs.ovhcloud.com/en/guides/public-cloud/cross-functional/create-and-delete-a-user)
  on the project, for the shared filesystem share network
* A [Hugging Face](https://huggingface.co/) token, only for gated models

> Use `tofu`, not `terraform`. The configuration is written for OpenTofu and
> declares `opentofu/helm` and `opentofu/openstack` as providers.

## Configure the deployment

### Configure the OVHcloud Tofu provider

Create an OVHcloud API token:

https://api.ovh.com/createToken?GET=/\*&POST=/\*&PUT=/\*&DELETE=/\*

Configure Tofu with this token:

```bash
vim ovhrc.sh
```

```bash
export OVH_ENDPOINT="ovh-eu"
export OVH_APPLICATION_KEY="<your_application_key>"
export OVH_APPLICATION_SECRET="<your_application_secret>"
export OVH_CONSUMER_KEY="<your_consumer_key>"
export OVH_CLOUD_PROJECT_SERVICE="<your_public_cloud_project_ID>"
```

### Configure the Tofu OpenStack provider

The shared filesystem service needs a share network, which the OVHcloud API does
not expose, so it is created through the OpenStack API.

Use this documentation to create an OpenStack user:
https://docs.ovhcloud.com/en/guides/public-cloud/cross-functional/create-and-delete-a-user

And this documentation to download the `openrc.sh` file:
https://docs.ovhcloud.com/en/guides/public-cloud/cross-functional/compute-set-openstack-environment-variables

The provider reads the `OS_*` variables that sourcing `openrc.sh` exports, so
keep the file as it was downloaded next to the configuration rather than copying
its contents into `ovhrc.sh`.

This is only needed while `model_cache_enabled` is `true`. Set it to `false` and
neither the CSI driver nor the share network is deployed, and the OpenStack user
becomes unnecessary.

### Configure the DNS credentials

You should create a second OVHcloud credential specific for the DNS
configuration with limited permissions (better for security). ExternalDNS and
cert-manager use it to publish the Open WebUI record and to solve the ACME
DNS-01 challenge.

Create an API token with the following permissions:
https://www.ovh.com/auth/api/createToken

```
GET on /domain/zone
GET on /domain/zone/*/record
GET on /domain/zone/*/record/*
POST on /domain/zone/*/record
DELETE on /domain/zone/*/record/*
GET on /domain/zone/*/soa
POST on /domain/zone/*/refresh
```

Add at the end of `ovhrc.sh`:

```bash
export TF_VAR_ovh_api_dns_application_key="<your_dns_application_key>"
export TF_VAR_ovh_api_dns_application_secret="<your_dns_application_secret>"
export TF_VAR_ovh_api_dns_consumer_key="<your_dns_consumer_key>"
```

### Configure the Hugging Face token

Only required for gated models. Add it to `ovhrc.sh` rather than to
`terraform.tfvars`, so it is never committed:

```bash
export TF_VAR_huggingface_token="<your_hugging_face_token>"
```

## Customize the deployment

```bash
vim terraform.tfvars
```

```bash
service_name   = "<your_ovh_public_cloud_project_id>"
ovh_dns_domain = "<your_ovh_domain_name>"
acme_email     = "<your_email_address>"

prefix_name = "mks-kubeai"
region      = "GRA11"

open_webui_subdomain     = "ai"
open_webui_admin_email   = "<your_email_address>"
open_webui_admin_password = "<a_strong_password>"

node_pools = [
  {
    name               = "control-plane"
    flavor             = "b3-8"
    desired_nodes      = "3"
    max_nodes          = "5"
    min_nodes          = "0"
    availability_zones = []
  },
  {
    name               = "compute-gpu"
    flavor             = "l4-90"
    autoscale          = true
    min_nodes          = "1"
    max_nodes          = "3"
    availability_zones = []

    # Declared on the pool so the autoscaler can grow it from zero: it simulates
    # a node from this template, and the KubeAI resource profile of the models
    # selects on exactly these labels. Keep them in sync with the flavor.
    labels = {
      "nvidia.com/gpu.family" = "ada-lovelace"
      "nvidia.com/gpu.memory" = "23034"
    }

    # Reserves the pool for the KubeAI models. Do not change the key, value or
    # effect: the tolerations of the KubeAI resource profiles, of the GPU
    # operator operands and of the node feature discovery worker all match
    # "nvidia.com/gpu=present:NoSchedule" exactly.
    taints = [{
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NoSchedule"
    }]
  },
]
```

You can find the list of configuration variables in `variables.tf` and you can
override the default values in `terraform.tfvars`.

## Deploy

```bash
source ovhrc.sh
source openrc.sh
tofu init
tofu plan
tofu apply
```

The first apply takes around 30 minutes: the managed databases, the ACME
certificate and the first pull of the 14 GB vLLM image all run in it.

Write the kubeconfig and check the cluster:

```bash
tofu output -raw kubeconfig_file > kubeconfig
export KUBECONFIG=./kubeconfig

kubectl get nodes
kubectl get pods -n kubeai
kubectl get models -n kubeai
```

Open WebUI is then served at the address printed by:

```bash
tofu output open_webui_url
```

## Deploy models

Model manifests are KubeAI `Model` custom resources, one per file:

| Directory | Applied? | Purpose |
| --- | --- | --- |
| `manifests/models` | Yes, by `tofu apply` | The models actually deployed. Read from `models_path`. |
| `manifests/models-examples` | No | Ready-made manifests to copy into `manifests/models`. |

Add a model by copying a file into `manifests/models` and running `tofu apply`.
A model opts into the weight cache by naming the profile in its `cacheProfile`
field, which must match `model_cache_profile_name`; when `model_cache_enabled` is
`false` the field is stripped from every manifest automatically.

A load test that exercises the model autoscaler lives in `test/`:

```bash
kubectl apply -f test/model-load-job.yaml
kubectl logs -n kubeai job/model-load -f
kubectl get pods -n kubeai -l kubeai.org/model=<model-name> -w
kubectl delete -f test/model-load-job.yaml
```

## Destroy

```bash
tofu destroy
```

## Configuration options

Required variables have no default and must be set in `terraform.tfvars` or
through a `TF_VAR_` environment variable. Descriptions here are shortened;
`variables.tf` carries the full rationale for each one.

### Global

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `service_name` | string | **required** | OVHcloud Public Cloud project ID |
| `prefix_name` | string | `mks-kubeai` | Prefix prepended to the name of every resource |
| `region` | string | `GRA11` | Public Cloud region hosting the private network and the cluster |

### Network

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `private_network_vlan_id` | string | `1` | vRack VLAN ID, also used to build the subnet CIDR (`10.<vlan_id>.0.0/16`) |
| `gateway_size` | string | `s` | Size of the public cloud gateway (`s`, `m`, `l`, `xl`, `2xl`) |
| `private_network_routing_as_default` | bool | `true` | Route node egress through the gateway rather than each node's public interface. Gives one stable exit address, bounded by the gateway bandwidth. |

### Kubernetes

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `kubernetes_version` | string | `1.34` | Managed Kubernetes Service version |
| `kubernetes_plan` | string | `free` | MKS plan (`free` or `standard`) |
| `node_pools` | list(object) | see `variables.tf` | Node pool parameters: name, flavor, sizing, autoscaling, labels and taints. Names are prefixed with `prefix_name`. |
| `platform_node_pool` | string | `control-plane` | Pool (unprefixed) running the platform components: ingress, ExternalDNS, cert-manager, the KubeAI controller and Open WebUI |

### Ingress

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `ingress_private` | string | `false` | Expose the ingress controller on an internal load balancer instead of a public one |
| `ingress_proxy_protocol` | bool | `true` | Carry the real client IP from the load balancer with the PROXY protocol. Required for the allow list and the rate limits to key on client addresses. |
| `ingress_quic` | bool | `false` | Serve HTTP/3 over QUIC. Off because UDP through the OVHcloud load balancer cannot carry the PROXY protocol, so the advertised endpoint is unreachable. |
| `ingress_replica_count` | string | `2` | Number of HAProxy ingress controller replicas |

### DNS and certificates

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `ovh_dns_domain` | string | **required** | OVHcloud DNS zone managed by ExternalDNS and used for the ACME DNS-01 challenge |
| `acme_email` | string | **required** | Email address registered on the Let's Encrypt account |
| `ovh_api_dns_application_key` | string | **required** | API application key allowed to manage the DNS zone |
| `ovh_api_dns_application_secret` | string (sensitive) | **required** | API application secret allowed to manage the DNS zone |
| `ovh_api_dns_consumer_key` | string (sensitive) | **required** | API consumer key allowed to manage the DNS zone |
| `ovh_api_endpoint` | string | `ovh-eu` | OVHcloud API endpoint |
| `external_dns_policy` | string | `sync` | ExternalDNS policy (`sync`, `upsert-only`, `create-only`) |
| `certificate_issuer` | string | `letsencrypt-production` | cert-manager ClusterIssuer signing the Open WebUI certificate |

### GPU operator

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `gpu_operator_use_precompiled_driver` | bool | `true` | Load a kernel module NVIDIA already built for the node's kernel. Removes the minutes a new node spends compiling one, and ties the pool to the kernels NVIDIA publishes for. |
| `gpu_operator_driver_version` | string | `595` | Driver version. With the precompiled driver, the major version alone; the operator completes it with the node kernel. Empty uses the chart default. |

### Image mirror (Spegel)

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `spegel_enabled` | bool | `true` | Deploy the image mirror, letting a node take image layers from a peer over the private network instead of the registry |
| `spegel_configure_containerd` | bool | `true` | Let the mirror write the containerd settings it needs on every node, at the cost of one containerd restart there |
| `spegel_mirrored_registries` | list(string) | `docker.io`, `ghcr.io`, `quay.io`, `registry.k8s.io`, `nvcr.io` | Registries a pull may resolve from a peer. Empty means every registry. |
| `spegel_max_concurrent_downloads` | number | `6` | Layers containerd fetches at once. Bounds the pull of an image whose weight sits in a few large layers. |
| `spegel_max_concurrent_unpacks` | number | `3` | Layers containerd decompresses at once. What a pull waits on once bytes arrive at local network speed. |
| `spegel_concurrent_layer_fetch_buffer` | number | `0` | Bytes buffered per layer in flight. Tens of megabytes lets a fetch run ahead of the unpack consuming it, at that much memory per layer. |

### Valkey

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `valkey_version` | string | `8.1` | Valkey version of the managed cluster (`8.1` or `9.1`) |
| `valkey_plan` | string | `production` | `essential` runs a single node, `production` a pair with an SLA |
| `valkey_flavor` | string | `b3-8` | Node flavor. Only configuration and sessions are stored, so the smallest flavor of the plan is enough. |

### PostgreSQL

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `postgresql_version` | string | `17` | PostgreSQL major version of the managed cluster |
| `postgresql_plan` | string | `production` | `discovery` runs a single node, `production` a pair with an SLA |
| `postgresql_flavor` | string | `b3-8` | Node flavor of the managed PostgreSQL cluster |

### KubeAI and Open WebUI

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `huggingface_token` | string (sensitive) | `""` | Token KubeAI uses to download models. Set it through `TF_VAR_huggingface_token`; do not commit it. |
| `models_path` | string | `manifests/models` | Directory, relative to the configuration, holding the KubeAI `Model` manifests to deploy |
| `model_cache_enabled` | bool | `true` | Cache the weights on a shared filesystem, downloaded once and read over the private network by every replica. `false` declares no cache profile, strips `cacheProfile` from the manifests, and deploys neither the CSI driver nor the share network. |
| `model_cache_profile_name` | string | `shared-filesystem` | Name of the cache profile a model names in its `cacheProfile` field |
| `model_cache_size` | string | `150Gi` | Size of the shared volume. 150Gi is the smallest share the `standard-1az` type will create. |
| `open_webui_subdomain` | string | `kubeai` | Subdomain of `ovh_dns_domain` exposing Open WebUI |
| `open_webui_admin_email` | string | `admin@example.com` | Email address of the Open WebUI admin account |
| `open_webui_admin_password` | string (sensitive) | `OVHcloud123!` | Password of the admin account. **Change this.** |
| `open_webui_enable_signup` | string | `True` | Let people register themselves |
| `open_webui_default_user_role` | string | `pending` | Role given to a new user. `pending` means an administrator must activate the account. |
| `open_webui_public_models` | string | `True` | Let every user reach every model. `False` keeps Open WebUI access control, which hides a model until it is granted public access in *Workspace > Models*. |
| `open_webui_replica_count` | number | `1` | Number of Open WebUI pods. One is the safe value for a first apply, since the schema migration takes no lock. |
| `open_webui_allow_list` | list(string) | `[]` | Addresses and CIDRs allowed to reach Open WebUI, interface and API alike. Empty means any address. |
| `open_webui_rate_limit_requests` | string | `600` | Requests accepted per token per window. Empty disables rate limiting. |
| `open_webui_rate_limit_unauthenticated_requests` | string | `300` | Requests accepted per client address per window for traffic carrying no token |
| `open_webui_rate_limit_window` | string | `1m` | Window both rate limits are measured over (`10s`, `1m`, `1h`) |

## Outputs

| Output | Description |
| --- | --- |
| `open_webui_url` | URL of Open WebUI |
| `kubeconfig_file` | kubeconfig of the cluster (sensitive) |
| `cluster_id`, `cluster_name` | Managed Kubernetes cluster identifiers |
| `kubeai_namespace` | Namespace where KubeAI and Open WebUI are deployed |
| `ingress_class`, `ingress_ip` | Default IngressClass and the load balancer address |
| `cluster_issuers` | ClusterIssuers available to sign certificates |
| `dns_domain` | DNS zone managed by ExternalDNS |
| `private_network_id`, `private_subnet_cidr`, `gateway_ips` | Private network, subnet CIDR and gateway public IPs |
| `valkey_host`, `valkey_port`, `valkey_username`, `valkey_password` | Managed Valkey endpoint and credentials |
| `postgresql_host`, `postgresql_port`, `postgresql_username`, `postgresql_password`, `postgresql_database` | Managed PostgreSQL endpoint and credentials |
| `bucket_name`, `bucket_endpoint_url` | Object Storage bucket holding the Open WebUI uploads |
