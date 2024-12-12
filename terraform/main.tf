terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }
  }

  backend "s3" {
    # key = -backend-config
    # region = -backend-config
    # profile = "-backend-config"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  # profile = $AWS_PROFILE
  # region = $AWS_REGION

  default_tags {
    tags = {
      Application = var.app_name
    }
  }
}

provider "cloudflare" {
  # api_token =  = $CLOUDFLARE_API_TOKEN
}

locals {
  root_zone_name = "acikgozb.dev"
}

resource "random_bytes" "bucket_id" {
  keepers = {
    app_name = var.app_name
  }

  length = 6
}

resource "aws_s3_bucket" "acikgozb-dev" {
  bucket = "${var.app_name}-${random_bytes.bucket_id.hex}"
  tags = {
    Name = "site-bucket"
  }
}

data "external" "cloudflare-cidr-ranges" {
  program = ["bash", "${path.module}/scripts/cloudflare-proxy-cidr"]
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions = ["s3:GetObject"]

    resources = [aws_s3_bucket.acikgozb-dev.arn]

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = jsondecode(data.external.cloudflare-cidr-ranges.result.list)
    }
  }

  depends_on = [data.external.cloudflare-cidr-ranges]
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.acikgozb-dev.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

data "cloudflare_zone" "root" {
  name = local.root_zone_name
}

resource "cloudflare_cloud_connector_rules" "acikgozb-dev" {
  zone_id = data.cloudflare_zone.root.id

  rules {
    description = "Connect static S3 bucket to root zone."
    enabled     = true
    expression  = "http.uri"
    provider    = "aws_s3"

    parameters {
      host = aws_s3_bucket.acikgozb-dev.bucket_regional_domain_name
    }
  }
}
