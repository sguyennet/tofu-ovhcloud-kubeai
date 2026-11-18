output "bucket_name" {
  description = "Name of the bucket"
  value       = ovh_cloud_project_storage.bucket.name
}

output "region" {
  description = "Region hosting the bucket, as the S3 API names it"
  value       = lower(ovh_cloud_project_storage.bucket.region)
}

# The S3 endpoint of a region, which is not the virtual host of the bucket: the
# client is given the service address and adds the bucket to it itself.
output "endpoint_url" {
  description = "S3 endpoint serving the bucket"
  value       = "https://s3.${lower(ovh_cloud_project_storage.bucket.region)}.io.cloud.ovh.net"
}

output "virtual_host" {
  description = "Virtual host of the bucket"
  value       = ovh_cloud_project_storage.bucket.virtual_host
}

output "access_key_id" {
  description = "S3 access key ID of the user owning the bucket"
  value       = ovh_cloud_project_user_s3_credential.owner.access_key_id
  sensitive   = true
}

output "secret_access_key" {
  description = "S3 secret access key of the user owning the bucket"
  value       = ovh_cloud_project_user_s3_credential.owner.secret_access_key
  sensitive   = true
}
