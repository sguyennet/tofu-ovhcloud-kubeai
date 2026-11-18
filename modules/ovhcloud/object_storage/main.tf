# The bucket is owned by a user of its own, whose S3 credentials are the only ones
# handed to the application.
resource "ovh_cloud_project_user" "owner" {
  service_name = var.service_name
  description  = var.user_description
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "owner" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.owner.id
}

resource "ovh_cloud_project_storage" "bucket" {
  service_name = var.service_name
  region_name  = var.region
  name         = var.bucket_name
  owner_id     = ovh_cloud_project_user.owner.id

  versioning = {
    status = var.versioning
  }

  encryption = {
    sse_algorithm = var.encryption_algorithm
  }
}

# objectstore_operator alone grants nothing on the objects, the policy is what
# opens the bucket to its owner, and to nothing else.
resource "ovh_cloud_project_user_s3_policy" "owner" {
  service_name = var.service_name
  user_id      = ovh_cloud_project_user.owner.id

  policy = jsonencode({
    Statement = [{
      Sid    = "Bucket"
      Effect = "Allow"
      Action = ["s3:*"]
      Resource = [
        "arn:aws:s3:::${ovh_cloud_project_storage.bucket.name}",
        "arn:aws:s3:::${ovh_cloud_project_storage.bucket.name}/*",
      ]
    }]
  })
}
