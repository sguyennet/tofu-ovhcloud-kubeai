variable "chart_version" {
  description = "haproxytech/kubernetes-ingress chart version"
  type        = string
  default     = "1.53.1"
}

variable "namespace" {
  description = "Namespace where the HAProxy ingress controller is deployed"
  type        = string
  default     = "haproxy-ingress"
}

variable "ingress_class" {
  description = "Name of the IngressClass handled by this controller"
  type        = string
  default     = "haproxy"
}

variable "default_ingress_class" {
  description = "Make this IngressClass the cluster default"
  type        = string
  default     = "true"

  validation {
    condition     = can(regex("^(true|false)$", var.default_ingress_class))
    error_message = "Default ingress class is a bool. Value have to be true or false."
  }
}

variable "replica_count" {
  description = "Number of HAProxy ingress controller replicas"
  type        = string
  default     = "2"
}

variable "private" {
  description = "Expose the controller through an internal (private network) load balancer"
  type        = string
  default     = "false"

  validation {
    condition     = can(regex("^(true|false)$", var.private))
    error_message = "Private is a bool. Value have to be true or false."
  }
}

variable "ssl_redirect" {
  description = "Redirect HTTP traffic to HTTPS"
  type        = string
  default     = "true"

  validation {
    condition     = can(regex("^(true|false)$", var.ssl_redirect))
    error_message = "SSL redirect is a bool. Value have to be true or false."
  }
}

variable "node_selector" {
  description = "Node labels the controller pods are pinned to"
  type        = map(string)
  default     = {}
}








variable "external_traffic_policy" {
  description = "Local stops kube-proxy from replacing the address of the client with the address of a node. Necessary to see real client IPs, but not sufficient on its own, see proxy_protocol_trusted_cidrs."
  type        = string
  default     = "Local"

  validation {
    condition     = can(regex("^(Local|Cluster)$", var.external_traffic_policy))
    error_message = "The external traffic policy must be either Local or Cluster"
  }
}

variable "proxy_protocol_trusted_cidrs" {
  description = "Networks the load balancer connects from, from which the controller accepts the PROXY protocol. Setting this also asks the OVHcloud load balancer to send it. This is what actually carries the client IP: the load balancer terminates the TCP connection, so without it every client looks like the load balancer whatever externalTrafficPolicy says."
  type        = list(string)
  default     = []
}

variable "quic" {
  description = <<-EOT
    Serve HTTP/3 over QUIC. It needs UDP through the load balancer, which cannot
    carry the PROXY protocol on OVHcloud, so the controller would advertise in
    every response an alt-svc endpoint that browsers cannot reach. They retry it
    as often as the advertisement expires, wait for it to time out, then fall
    back to TCP, which reads as a site that works but is slow. curl never sees
    it, it does not try HTTP/3.

    Beware when flipping this value on a running cluster. The QUIC port reuses
    the number of the HTTPS port, 443 on the service and 8443 on the container,
    and both lists are merged by Kubernetes on those numbers as a key. Removing
    the QUIC entry therefore takes the HTTPS entry with it, the manifest of the
    release keeps both while the live objects lose 443 entirely, and HTTPS stops
    answering. Helm sees nothing to do afterwards, since its own manifest is
    correct, so the live objects have to be patched by hand:

      kubectl -n <namespace> patch svc <release>-kubernetes-ingress --type=json \
        -p '[{"op":"add","path":"/spec/ports/-","value":{"name":"https","port":443,"protocol":"TCP","appProtocol":"https","targetPort":"https"}}]'

      kubectl -n <namespace> patch deploy <release>-kubernetes-ingress --type=json \
        -p '[{"op":"add","path":"/spec/template/spec/containers/0/ports/-","value":{"name":"https","containerPort":8443,"protocol":"TCP"}}]'
  EOT

  type    = bool
  default = false
}
