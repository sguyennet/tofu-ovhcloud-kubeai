variable "service_name" {
  description = "OVHcloud Public Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32}$", var.service_name))
    error_message = "The service name is not a project ID"
  }
}

variable "region" {
  description = "Region hosting the bucket. Object Storage is placed in a macro region (GRA) rather than in one of its availability zones (GRA11)."
  type        = string

  validation {
    condition     = can(regex("^[A-Z]+(-[A-Z]+)*[0-9]*$", var.region))
    error_message = "The region is not valid"
  }
}

variable "user_description" {
  description = "Description of the Public Cloud user owning the bucket, as displayed in the OVHcloud control panel"
  type        = string
}

variable "bucket_name" {
  description = "Name of the bucket. It has to be unique in the region."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "The bucket name must be between 3 and 63 characters of lowercase letters, digits, dots and hyphens, and start and end with a letter or a digit"
  }
}

variable "versioning" {
  description = "Keep the previous versions of an overwritten or deleted object"
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["enabled", "disabled"], var.versioning)
    error_message = "Versioning must be either enabled or disabled"
  }
}

variable "encryption_algorithm" {
  description = "Server side encryption of the objects at rest"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "plaintext"], var.encryption_algorithm)
    error_message = "The encryption algorithm must be either AES256 or plaintext"
  }
}
