variable "dc_region" {
  description = "Region for Rancher + DC cluster"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Region for the DR S3 bucket (cross-region copy)"
  type        = string
  default     = "us-west-2"
}

variable "key_name" {
  description = "Existing EC2 key pair name (e.g. rancher)"
  type        = string
  default     = "rancher"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form for SSH/UI access, e.g. 122.161.75.225/32"
  type        = string
}

variable "instance_type" {
  description = "Instance type for Rancher server and DC nodes (t3.large recommended for RKE2)"
  type        = string
  default     = "t3.large"
}

variable "root_disk_gb" {
  description = "Root EBS size in GB (>=30 for RKE2/containers)"
  type        = number
  default     = 30
}

variable "dc_node_count" {
  description = "Number of DC cluster nodes (etcd+cp+worker). 3 = HA quorum."
  type        = number
  default     = 3
}

variable "rancher_version" {
  description = "Rancher image tag"
  type        = string
  default     = "v2.10.1"
}

variable "name_prefix" {
  description = "Prefix for resource names so they don't clash with existing instances"
  type        = string
  default     = "tf-dcdr"
}

variable "dc_bucket_name" {
  description = "Globally-unique name for the DC pgBackRest S3 bucket"
  type        = string
}

variable "dr_bucket_name" {
  description = "Globally-unique name for the DR pgBackRest S3 bucket"
  type        = string
}
