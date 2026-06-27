terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# DC region (where Rancher server + DC cluster nodes live)
provider "aws" {
  region = var.dc_region
}

# DR region (only used for the DR S3 bucket = cross-region copy target)
provider "aws" {
  alias  = "dr"
  region = var.dr_region
}
