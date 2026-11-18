output "storage_class_name" {
  description = "StorageClass provisioning shares with ReadWriteMany access"
  value       = kubectl_manifest.storage_class.name
}

output "share_network_id" {
  description = "Share network binding the shares to the private network"
  value       = openstack_sharedfilesystem_sharenetwork_v2.share_network.id
}
